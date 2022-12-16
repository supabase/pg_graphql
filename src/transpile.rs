use crate::builder::*;
use crate::graphql::*;
use crate::gson;
use crate::parser_util::json_to_gson;
use crate::sql_types::{Column, ForeignKey, ForeignKeyTableInfo, Table};
use pgx::pg_sys::submodules::panic::CaughtError;
use pgx::prelude::*;
use pgx::*;
use pgx_contrib_spiext::{checked::*, subtxn::*};
use serde::ser::{Serialize, SerializeMap, Serializer};
use std::cmp;
use std::sync::Arc;

pub fn quote_ident(ident: &str) -> String {
    unsafe {
        direct_function_call::<String>(pg_sys::quote_ident, vec![ident.into_datum()]).unwrap()
    }
}

pub fn quote_literal(ident: &str) -> String {
    unsafe {
        direct_function_call::<String>(pg_sys::quote_literal, vec![ident.into_datum()]).unwrap()
    }
}

pub fn rand_block_name() -> String {
    use rand::distributions::Alphanumeric;
    use rand::{thread_rng, Rng};
    quote_ident(
        &thread_rng()
            .sample_iter(&Alphanumeric)
            .take(7)
            .map(char::from)
            .collect::<String>()
            .to_lowercase(),
    )
}

pub trait MutationEntrypoint<'conn> {
    fn to_sql_entrypoint(&self, param_context: &mut ParamContext) -> Result<String, String>;

    fn execute(
        &self,
        xact: SubTransaction<Box<SpiClient<'conn>>>,
    ) -> Result<(serde_json::Value, SubTransaction<Box<SpiClient<'conn>>>), String> {
        let mut param_context = ParamContext { params: vec![] };
        let sql = &self.to_sql_entrypoint(&mut param_context);
        let sql = match sql {
            Ok(sql) => sql,
            Err(err) => {
                xact.rollback();
                return Err(err.to_string());
            }
        };

        let (res_q, next_xact) = xact
            .checked_update(sql, None, Some(param_context.params))
            .map_err(|err| match err {
                CaughtError::PostgresError(error) => error.message().to_string(),
                _ => "Internal Error: Failed to execute transpiled query".to_string(),
            })?;

        let res: pgx::JsonB = match res_q.first().get_datum::<pgx::JsonB>(1) {
            Some(dat) => dat,
            None => {
                next_xact.rollback();
                return Err(
                    "Internal Error: Failed to load result from transpiled query".to_string(),
                );
            }
        };

        Ok((res.0, next_xact))
    }
}

pub trait QueryEntrypoint {
    fn to_sql_entrypoint(&self, param_context: &mut ParamContext) -> Result<String, String>;

    fn execute(&self) -> Result<serde_json::Value, String> {
        let mut param_context = ParamContext { params: vec![] };
        let sql = &self.to_sql_entrypoint(&mut param_context);
        let sql = match sql {
            Ok(sql) => sql,
            Err(err) => {
                return Err(err.to_string());
            }
        };

        let spi_result: Option<Result<Option<pgx::JsonB>, CaughtError>> = Spi::connect(|c| {
            //Create subtransaction
            let sub_txn_result: Result<Option<pgx::JsonB>, CaughtError> =
                c.sub_transaction(|xact| {
                    let (val, _) = xact.checked_select(sql, Some(1), Some(param_context.params))?;
                    // Get a value from the query
                    let out_val: Option<pgx::JsonB> = val.first().get_datum::<pgx::JsonB>(1);
                    Ok(out_val)
                });

            // Return that value from the closure
            Ok(Some(sub_txn_result))
        });

        match spi_result {
            Some(Ok(Some(jsonb))) => Ok(jsonb.0),
            Some(Ok(None)) => Ok(serde_json::Value::Null),
            _ => Err("Internal Error: Failed to execute transpiled query".to_string()),
        }
    }
}

impl Table {
    fn to_selectable_columns_clause(&self) -> String {
        self.columns
            .iter()
            .filter(|x| x.permissions.is_selectable)
            .map(|x| quote_ident(&x.name))
            .collect::<Vec<String>>()
            .join(", ")
    }

    /// a priamry key tuple clause selects the columns of the primary key as a composite record
    /// that is useful in "has_previous_page" by letting us compare records on a known unique key
    fn to_primary_key_tuple_clause(&self, block_name: &str) -> String {
        let pkey_cols: Vec<&Arc<Column>> = self.primary_key_columns();

        let pkey_frags: Vec<String> = pkey_cols
            .iter()
            .map(|x| format!("{block_name}.{}", quote_ident(&x.name)))
            .collect();

        format!("({})", pkey_frags.join(","))
    }

    fn to_cursor_clause(&self, block_name: &str, order_by: &OrderByBuilder) -> String {
        let frags: Vec<String> = order_by
            .elems
            .iter()
            .map(|x| {
                let quoted_col_name = quote_ident(&x.column.name);
                format!("to_jsonb({block_name}.{quoted_col_name})")
            })
            .collect();

        let clause = frags.join(", ");

        format!("translate(encode(convert_to(jsonb_build_array({clause})::text, 'utf-8'), 'base64'), E'\n', '')")
    }

    fn to_pagination_clause(
        &self,
        block_name: &str,
        order_by: &OrderByBuilder,
        cursor: &Cursor,
        param_context: &mut ParamContext,
        allow_equality: bool,
    ) -> Result<String, String> {
        // When paginating, allowe_equality should be false because we don't want to
        // include the cursor's record in the page
        //
        // when checking to see if a previous page exists, allow_equality should be
        // true, in combination with a reversed order_by because the existence of the
        // cursor's record proves that there is a previous page

        // [id asc, name desc]
        /*
        "(
            ( id > x1  or ( id is not null and x1 is null and <nulls_first>))
            or (( id = x1 or ( id is null and x1 is null )) and  <recurse>)

        )"
        */
        if cursor.elems.is_empty() {
            return Ok(format!("{allow_equality}"));
        }
        let mut next_cursor = cursor.clone();
        let cursor_elem = next_cursor.elems.remove(0);

        if order_by.elems.is_empty() {
            return Err("orderBy clause incompatible with pagination cursor".to_string());
        }
        let mut next_order_by = order_by.clone();
        let order_elem = next_order_by.elems.remove(0);

        let column = order_elem.column;
        let quoted_col = quote_ident(&column.name);

        let val: gson::Value = json_to_gson(&cursor_elem.value)?;

        let val_clause = param_context.clause_for(&val, &column.type_name)?;

        let recurse_clause = self.to_pagination_clause(
            block_name,
            &next_order_by,
            &next_cursor,
            param_context,
            allow_equality,
        )?;

        let nulls_first: bool = order_elem.direction.nulls_first();

        let op = match order_elem.direction.is_asc() {
            true => ">",
            false => "<",
        };

        Ok(format!("(
            ( {block_name}.{quoted_col} {op} {val_clause}  or ( {block_name}.{quoted_col} is not null and {val_clause} is null and {nulls_first}))
            or (( {block_name}.{quoted_col} = {val_clause} or ( {block_name}.{quoted_col} is null and {val_clause} is null)) and  {recurse_clause})

        )"))
    }

    fn to_join_clause(
        &self,
        fkey: &ForeignKey,
        reverse_reference: bool,
        quoted_block_name: &str,
        quoted_parent_block_name: &str,
    ) -> Result<String, String> {
        let mut equality_clauses = vec!["true".to_string()];

        let table_ref: &ForeignKeyTableInfo;
        let foreign_ref: &ForeignKeyTableInfo;

        match reverse_reference {
            true => {
                table_ref = &fkey.local_table_meta;
                foreign_ref = &fkey.referenced_table_meta;
            }
            false => {
                table_ref = &fkey.referenced_table_meta;
                foreign_ref = &fkey.local_table_meta;
            }
        };

        for (local_col_name, parent_col_name) in table_ref
            .column_names
            .iter()
            .zip(foreign_ref.column_names.iter())
        {
            let quoted_parent_literal_col = format!(
                "{}.{}",
                quoted_parent_block_name,
                quote_ident(parent_col_name)
            );
            let quoted_local_literal_col =
                format!("{}.{}", quoted_block_name, quote_ident(local_col_name));

            let equality_clause = format!(
                "{} = {}",
                quoted_local_literal_col, quoted_parent_literal_col
            );

            equality_clauses.push(equality_clause);
        }
        Ok(equality_clauses.join(" and "))
    }
}

impl MutationEntrypoint<'_> for InsertBuilder {
    fn to_sql_entrypoint(&self, param_context: &mut ParamContext) -> Result<String, String> {
        let quoted_block_name = rand_block_name();
        let quoted_schema = quote_ident(&self.table.schema);
        let quoted_table = quote_ident(&self.table.name);

        let frags: Vec<String> = self
            .selections
            .iter()
            .map(|x| x.to_sql(&quoted_block_name, param_context))
            .collect::<Result<Vec<_>, _>>()?;

        let selectable_columns_clause = self.table.to_selectable_columns_clause();

        let select_clause = frags.join(", ");

        let columns: &Vec<Arc<Column>> = &self.table.columns;

        let mut values_rows_clause: Vec<String> = vec![];

        for row_map in &self.objects {
            let mut working_row = vec![];
            for column in columns {
                let elem_clause = match row_map.row.get(&column.name) {
                    None => "default".to_string(),
                    Some(elem) => match elem {
                        InsertElemValue::Default => "default".to_string(),
                        InsertElemValue::Value(val) => {
                            param_context.clause_for(val, &column.type_name)?
                        }
                    },
                };
                working_row.push(elem_clause);
            }
            // (1, 'hello', 5)
            let insert_row_clause = format!("({})", working_row.join(", "));
            values_rows_clause.push(insert_row_clause);
        }

        let values_clause = values_rows_clause.join(", ");

        let column_names: Vec<String> = columns.iter().map(|x| quote_ident(&x.name)).collect();
        let columns_clause: String = column_names.join(", ");

        Ok(format!(
            "
        with affected as (
            insert into {quoted_schema}.{quoted_table}({columns_clause})
            values {values_clause}
            returning {selectable_columns_clause}
        )
        select
            jsonb_build_object({select_clause})
        from
            affected as {quoted_block_name};
        "
        ))
    }
}

impl InsertSelection {
    pub fn to_sql(
        &self,
        block_name: &str,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        let r = match self {
            Self::AffectedCount { alias } => {
                format!("{}, count(*)", quote_literal(alias))
            }
            Self::Records(x) => {
                format!(
                    "{}, coalesce(jsonb_agg({}), jsonb_build_array())",
                    quote_literal(&x.alias),
                    x.to_sql(block_name, param_context)?
                )
            }
            Self::Typename { alias, typename } => {
                format!("{}, {}", quote_literal(alias), quote_literal(typename))
            }
        };
        Ok(r)
    }
}

impl UpdateSelection {
    pub fn to_sql(
        &self,
        block_name: &str,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        let r = match self {
            Self::AffectedCount { alias } => {
                format!("{}, count(*)", quote_literal(alias))
            }
            Self::Records(x) => {
                format!(
                    "{}, coalesce(jsonb_agg({}), jsonb_build_array())",
                    quote_literal(&x.alias),
                    x.to_sql(block_name, param_context)?
                )
            }
            Self::Typename { alias, typename } => {
                format!("{}, {}", quote_literal(alias), quote_literal(typename))
            }
        };
        Ok(r)
    }
}

impl DeleteSelection {
    pub fn to_sql(
        &self,
        block_name: &str,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        let r = match self {
            Self::AffectedCount { alias } => {
                format!("{}, count(*)", quote_literal(alias))
            }
            Self::Records(x) => {
                format!(
                    "{}, coalesce(jsonb_agg({}), jsonb_build_array())",
                    quote_literal(&x.alias),
                    x.to_sql(block_name, param_context)?
                )
            }
            Self::Typename { alias, typename } => {
                format!("{}, {}", quote_literal(alias), quote_literal(typename))
            }
        };

        Ok(r)
    }
}

impl MutationEntrypoint<'_> for UpdateBuilder {
    fn to_sql_entrypoint(&self, param_context: &mut ParamContext) -> Result<String, String> {
        let quoted_block_name = rand_block_name();
        let quoted_schema = quote_ident(&self.table.schema);
        let quoted_table = quote_ident(&self.table.name);

        let frags: Vec<String> = self
            .selections
            .iter()
            .map(|x| x.to_sql(&quoted_block_name, param_context))
            .collect::<Result<Vec<_>, _>>()?;

        let select_clause = frags.join(", ");

        let set_clause: String = {
            let mut set_clause_frags = vec![];
            for (column_name, val) in &self.set.set {
                let quoted_column = quote_ident(column_name);

                let column: &Column = self
                    .table
                    .columns
                    .iter()
                    .find(|x| &x.name == column_name)
                    .expect("Failed to find field in update builder");

                let value_clause = param_context.clause_for(val, &column.type_name)?;

                let set_clause_frag = format!("{quoted_column} = {value_clause}");
                set_clause_frags.push(set_clause_frag);
            }
            set_clause_frags.join(", ")
        };

        let selectable_columns_clause = self.table.to_selectable_columns_clause();

        let where_clause =
            self.filter
                .to_where_clause(&quoted_block_name, &self.table, param_context)?;

        let at_most = self.at_most;

        Ok(format!(
            "
        with impacted as (
            update {quoted_schema}.{quoted_table} as {quoted_block_name}
            set {set_clause}
            where {where_clause}
            returning {selectable_columns_clause}
        ),
        total(total_count) as (
            select
                count(*)
            from
                impacted
        ),
        req(res) as (
            select
                jsonb_build_object({select_clause})
            from
                impacted {quoted_block_name}
            limit 1
        ),
        wrapper(res) as (
            select
                case
                    when total.total_count > {at_most} then graphql.exception($a$update impacts too many records$a$)::jsonb
                    else req.res
                end
            from
                total
                left join req
                    on true
            limit 1
        )
        select
            res
        from
            wrapper;
        "
        ))
    }
}

impl MutationEntrypoint<'_> for DeleteBuilder {
    fn to_sql_entrypoint(&self, param_context: &mut ParamContext) -> Result<String, String> {
        let quoted_block_name = rand_block_name();
        let quoted_schema = quote_ident(&self.table.schema);
        let quoted_table = quote_ident(&self.table.name);

        let frags: Vec<String> = self
            .selections
            .iter()
            .map(|x| x.to_sql(&quoted_block_name, param_context))
            .collect::<Result<Vec<_>, _>>()?;

        let select_clause = frags.join(", ");
        let where_clause =
            self.filter
                .to_where_clause(&quoted_block_name, &self.table, param_context)?;

        let selectable_columns_clause = self.table.to_selectable_columns_clause();

        let at_most = self.at_most;

        Ok(format!(
            "
        with impacted as (
            delete from {quoted_schema}.{quoted_table} as {quoted_block_name}
            where {where_clause}
            returning {selectable_columns_clause}
        ),
        total(total_count) as (
            select
                count(*)
            from
                impacted
        ),
        req(res) as (
            select
                jsonb_build_object({select_clause})
            from
                impacted {quoted_block_name}
            limit 1
        ),
        wrapper(res) as (
            select
                case
                    when total.total_count > {at_most} then graphql.exception($a$delete impacts too many records$a$)::jsonb
                    else req.res
                end
            from
                total
                left join req
                    on true
            limit 1
        )
        select
            res
        from
            wrapper;
        "
        ))
    }
}

impl OrderByBuilder {
    fn to_order_by_clause(&self, block_name: &str) -> String {
        let mut frags = vec![];

        for elem in &self.elems {
            let quoted_column_name = quote_ident(&elem.column.name);
            let direction_clause = match elem.direction {
                OrderDirection::AscNullsFirst => "asc nulls first",
                OrderDirection::AscNullsLast => "asc nulls last",
                OrderDirection::DescNullsFirst => "desc nulls first",
                OrderDirection::DescNullsLast => "desc nulls last",
            };
            let elem_clause = format!("{block_name}.{quoted_column_name} {direction_clause}");
            frags.push(elem_clause)
        }
        frags.join(", ")
    }
}

pub fn gson_to_text_datum(val: &gson::Value) -> Result<Option<pg_sys::Datum>, String> {
    let null: Option<i32> = None;
    match val {
        gson::Value::Null => Ok(null.into_datum()),
        gson::Value::Boolean(x) => Ok(x.to_string().into_datum()),
        gson::Value::String(x) => Ok(x.into_datum()),
        gson::Value::Number(gson::Number::Integer(x)) => Ok(x.to_string().into_datum()),
        gson::Value::Number(gson::Number::Float(x)) => Ok(x.to_string().into_datum()),
        gson::Value::Array(xarr) => {
            let inner_vals: Vec<Option<String>> = xarr
                .iter()
                .map(|x| match x {
                    gson::Value::Null => None,
                    gson::Value::Boolean(x) => Some(x.to_string()),
                    gson::Value::String(x) => Some(x.to_string()),
                    gson::Value::Number(gson::Number::Integer(x)) => Some(x.to_string()),
                    gson::Value::Number(gson::Number::Float(x)) => Some(x.to_string()),
                    gson::Value::Array(_) => panic!("Unexpected array in input value array"),
                    gson::Value::Object(_) => {
                        panic!("Unexpected object in input value array")
                    }
                    // Logic associated with absent values should always be handled in the
                    // builders. We should never see an absent value here.
                    gson::Value::Absent => {
                        panic!("Unexpected absent value in array")
                    }
                })
                .collect();
            Ok(inner_vals.into_datum())
        }
        // Should this ever happen? json input is escaped so it would be a string.
        gson::Value::Object(_) => Err("Unexpected object in input value".to_string()),
        // Logic associated with absent values should always be handled in the
        // builders. We should never see an absent value here.
        gson::Value::Absent => Err("Unexpected absent value".to_string()),
    }
}

pub struct ParamContext {
    pub params: Vec<(PgOid, Option<pg_sys::Datum>)>,
}

impl ParamContext {
    // Pushes a parameter into the context and returns a SQL clause to reference it
    //fn clause_for(&mut self, param: (PgOid, Option<pg_sys::Datum>)) -> String {
    fn clause_for(&mut self, value: &gson::Value, type_name: &String) -> Result<String, String> {
        let type_oid = match type_name.ends_with("[]") {
            true => PgOid::from(1009), // text[]
            false => PgOid::from(25),  // text
        };

        let val_datum = gson_to_text_datum(value)?;
        self.params.push((type_oid, val_datum));
        Ok(format!("(${}::{})", self.params.len(), type_name))
    }
}

impl FilterBuilderElem {
    fn to_sql(
        &self,
        block_name: &str,
        table: &Table,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        match self {
            Self::Column { column, op, value } => {
                let cast_type_name = match op {
                    FilterOp::In => format!("{}[]", column.type_name),
                    _ => column.type_name.clone(),
                };

                let val_clause = param_context.clause_for(value, &cast_type_name)?;

                let frag = format!(
                    "{block_name}.{} {} {}",
                    quote_ident(&column.name),
                    match op {
                        FilterOp::Equal => "=",
                        FilterOp::NotEqual => "<>",
                        FilterOp::LessThan => "<",
                        FilterOp::LessThanEqualTo => "<=",
                        FilterOp::GreaterThan => ">",
                        FilterOp::GreaterThanEqualTo => ">=",
                        FilterOp::In => "= any",
                    },
                    val_clause
                );
                Ok(frag)
            }
            Self::NodeId(node_id) => node_id.to_sql(block_name, table, param_context),
        }
    }
}

impl FilterBuilder {
    fn to_where_clause(
        &self,
        block_name: &str,
        table: &Table,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        let mut frags = vec!["true".to_string()];

        for elem in &self.elems {
            let frag = elem.to_sql(block_name, table, param_context)?;
            frags.push(frag);
        }
        Ok(frags.join(" and "))
    }
}

impl ConnectionBuilder {
    fn requested_total(&self) -> bool {
        self.selections
            .iter()
            .any(|x| matches!(&x, ConnectionSelection::TotalCount { alias: _ }))
    }

    fn page_selections(&self) -> Vec<PageInfoSelection> {
        self.selections
            .iter()
            .flat_map(|x| match x {
                ConnectionSelection::PageInfo(page_info_builder) => {
                    page_info_builder.selections.clone()
                }
                _ => vec![],
            })
            .collect()
    }

    fn requested_next_page(&self) -> bool {
        self.page_selections()
            .iter()
            .any(|x| matches!(&x, PageInfoSelection::HasNextPage { alias: _ }))
    }

    fn requested_previous_page(&self) -> bool {
        self.page_selections()
            .iter()
            .any(|x| matches!(&x, PageInfoSelection::HasPreviousPage { alias: _ }))
    }

    pub fn to_sql(
        &self,
        quoted_parent_block_name: Option<&str>,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        let quoted_block_name = rand_block_name();
        let quoted_schema = quote_ident(&self.table.schema);
        let quoted_table = quote_ident(&self.table.name);

        let where_clause =
            self.filter
                .to_where_clause(&quoted_block_name, &self.table, param_context)?;

        let order_by_clause = self.order_by.to_order_by_clause(&quoted_block_name);
        let order_by_clause_reversed = self
            .order_by
            .reverse()
            .to_order_by_clause(&quoted_block_name);

        let order_by_clause_records = match self.last.is_some() {
            true => &order_by_clause_reversed,
            false => &order_by_clause,
        };

        let requested_total = self.requested_total();
        let requested_next_page = self.requested_next_page();
        let requested_previous_page = self.requested_previous_page();

        let join_clause = match &self.fkey {
            Some(fkey) => {
                let quoted_parent_block_name = quoted_parent_block_name
                    .ok_or("Internal Error: Parent block name is required when fkey_ix is set")?;
                self.table.to_join_clause(
                    fkey,
                    self.reverse_reference.unwrap(),
                    &quoted_block_name,
                    quoted_parent_block_name,
                )?
            }
            None => "true".to_string(),
        };

        let frags: Vec<String> = self
            .selections
            .iter()
            .map(|x| {
                x.to_sql(
                    &quoted_block_name,
                    &self.order_by,
                    &self.table,
                    param_context,
                )
            })
            .collect::<Result<Vec<_>, _>>()?;

        let limit: i64 = cmp::min(self.first.unwrap_or_else(|| self.last.unwrap_or(30)), 30);

        let object_clause = frags.join(", ");

        let cursor = &self.before.clone().or_else(|| self.after.clone());

        let pagination_clause = {
            let order_by = match self.last.is_some() {
                true => self.order_by.reverse(),
                false => self.order_by.clone(),
            };
            match cursor {
                Some(cursor) => self.table.to_pagination_clause(
                    &quoted_block_name,
                    &order_by,
                    cursor,
                    param_context,
                    false,
                )?,
                None => "true".to_string(),
            }
        };

        let selectable_columns_clause = self.table.to_selectable_columns_clause();

        let pkey_tuple_clause_from_block =
            self.table.to_primary_key_tuple_clause(&quoted_block_name);
        let pkey_tuple_clause_from_records = self.table.to_primary_key_tuple_clause("__records");

        Ok(format!(
            "
            (
                with __records as (
                    select
                        {selectable_columns_clause}
                    from
                        {quoted_schema}.{quoted_table} {quoted_block_name}
                    where
                        true
                        and {join_clause}
                        and {where_clause}
                        and {pagination_clause}
                    order by
                        {order_by_clause_records}
                    limit
                        {limit}
                ),
                __total_count(___total_count) as (
                    select
                        count(*)
                    from
                        {quoted_schema}.{quoted_table} {quoted_block_name}
                    where
                        {requested_total} -- skips total when not requested
                        and {join_clause}
                        and {where_clause}
                ),
                __has_next_page(___has_next_page) as (
                    with page_plus_1 as (
                        select
                            1
                        from
                            {quoted_schema}.{quoted_table} {quoted_block_name}
                        where
                            {requested_next_page} -- skips when not requested
                            and {join_clause}
                            and {where_clause}
                            and {pagination_clause}
                        order by
                            {order_by_clause}
                        limit ({limit} + 1)
                    )
                    select count(*) > {limit} from page_plus_1
                ),
                __has_previous_page(___has_previous_page) as (
                    with page_minus_1 as (
                        select
                            not ({pkey_tuple_clause_from_block} = any( __records.seen )) is_pkey_in_records
                        from
                            {quoted_schema}.{quoted_table} {quoted_block_name}
                            left join (select array_agg({pkey_tuple_clause_from_records}) from __records ) __records(seen)
                                on true
                        where
                            {requested_previous_page} -- skips when not requested
                            and {join_clause}
                            and {where_clause}
                        order by
                            {order_by_clause_records}
                        limit 1
                    )
                    select coalesce(bool_and(is_pkey_in_records), false) from page_minus_1
                )
                select
                    jsonb_build_object({object_clause}) -- sorted within edge
                from
                    __records {quoted_block_name},
                    __total_count,
                    __has_next_page,
                    __has_previous_page
            )"
        ))
    }
}

impl QueryEntrypoint for ConnectionBuilder {
    fn to_sql_entrypoint(&self, param_context: &mut ParamContext) -> Result<String, String> {
        self.to_sql(None, param_context)
    }
}

impl PageInfoBuilder {
    pub fn to_sql(
        &self,
        _block_name: &str,
        order_by: &OrderByBuilder,
        table: &Table,
    ) -> Result<String, String> {
        let frags: Vec<String> = self
            .selections
            .iter()
            .map(|x| x.to_sql(_block_name, order_by, table))
            .collect::<Result<Vec<_>, _>>()?;

        let x = frags.join(", ");

        Ok(format!("jsonb_build_object({})", x,))
    }
}

impl PageInfoSelection {
    pub fn to_sql(
        &self,
        block_name: &str,
        order_by: &OrderByBuilder,
        table: &Table,
    ) -> Result<String, String> {
        let order_by_clause = order_by.to_order_by_clause(block_name);
        let order_by_clause_reversed = order_by.reverse().to_order_by_clause(block_name);

        let cursor_clause = table.to_cursor_clause(block_name, order_by);

        Ok(match self {
            Self::StartCursor { alias } => {
                format!(
                    "{}, (array_agg({cursor_clause} order by {order_by_clause}))[1]",
                    quote_literal(alias)
                )
            }
            Self::EndCursor { alias } => {
                format!(
                    "{}, (array_agg({cursor_clause} order by {order_by_clause_reversed}))[1]",
                    quote_literal(alias)
                )
            }
            Self::HasNextPage { alias } => {
                format!(
                    "{}, coalesce(bool_and(__has_next_page.___has_next_page), false)",
                    quote_literal(alias)
                )
            }
            Self::HasPreviousPage { alias } => {
                format!(
                    "{}, coalesce(bool_and(__has_previous_page.___has_previous_page), false)",
                    quote_literal(alias)
                )
            }
            Self::Typename { alias, typename } => {
                format!("{}, {}", quote_literal(alias), quote_literal(typename))
            }
        })
    }
}

impl ConnectionSelection {
    pub fn to_sql(
        &self,
        block_name: &str,
        order_by: &OrderByBuilder,
        table: &Table,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        Ok(match self {
            Self::Edge(x) => {
                format!(
                    "{}, {}",
                    quote_literal(&x.alias),
                    x.to_sql(block_name, order_by, table, param_context)?
                )
            }
            Self::PageInfo(x) => {
                format!(
                    "{}, {}",
                    quote_literal(&x.alias),
                    x.to_sql(block_name, order_by, table)?
                )
            }
            Self::TotalCount { alias } => {
                format!(
                    "{}, coalesce(min(__total_count.___total_count), 0)",
                    quote_literal(alias)
                )
            }
            Self::Typename { alias, typename } => {
                format!("{}, {}", quote_literal(alias), quote_literal(typename))
            }
        })
    }
}

impl EdgeBuilder {
    pub fn to_sql(
        &self,
        block_name: &str,
        order_by: &OrderByBuilder,
        table: &Table,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        let frags: Vec<String> = self
            .selections
            .iter()
            .map(|x| x.to_sql(block_name, order_by, table, param_context))
            .collect::<Result<Vec<_>, _>>()?;

        let x = frags.join(", ");
        let order_by_clause = order_by.to_order_by_clause(block_name);

        Ok(format!(
            "coalesce(
                jsonb_agg(
                    jsonb_build_object({x})
                    order by {order_by_clause}
                ),
                jsonb_build_array()
            )"
        ))
    }
}

impl EdgeSelection {
    pub fn to_sql(
        &self,
        block_name: &str,
        order_by: &OrderByBuilder,
        table: &Table,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        Ok(match self {
            Self::Cursor { alias } => {
                let cursor_clause = table.to_cursor_clause(block_name, order_by);
                format!("{}, {cursor_clause}", quote_literal(alias))
            }
            Self::Node(builder) => format!(
                "{}, {}",
                quote_literal(&builder.alias),
                builder.to_sql(block_name, param_context)?
            ),
            Self::Typename { alias, typename } => {
                format!("{}, {}", quote_literal(alias), quote_literal(typename))
            }
        })
    }
}

impl NodeBuilder {
    pub fn to_sql(
        &self,
        block_name: &str,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        let frags: Vec<String> = self
            .selections
            .iter()
            .map(|x| x.to_sql(block_name, param_context))
            .collect::<Result<Vec<_>, _>>()?;
        Ok(format!("jsonb_build_object({})", frags.join(", ")))
    }

    pub fn to_relation_sql(
        &self,
        parent_block_name: &str,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        let quoted_block_name = rand_block_name();
        let quoted_schema = quote_ident(&self.table.schema);
        let quoted_table = quote_ident(&self.table.name);

        let fkey = self.fkey.as_ref().ok_or("Internal Error: relation key")?;
        let reverse_reference = self
            .reverse_reference
            .ok_or("Internal Error: relation reverse reference")?;

        let frags: Vec<String> = self
            .selections
            .iter()
            .map(|x| x.to_sql(&quoted_block_name, param_context))
            .collect::<Result<Vec<_>, _>>()?;

        let object_clause = frags.join(", ");

        let join_clause = self.table.to_join_clause(
            fkey,
            reverse_reference,
            &quoted_block_name,
            parent_block_name,
        )?;

        Ok(format!(
            "
            (
                select
                    jsonb_build_object({object_clause})
                from
                    {quoted_schema}.{quoted_table} as {quoted_block_name}
                where
                    {join_clause}
            )"
        ))
    }
}

impl QueryEntrypoint for NodeBuilder {
    fn to_sql_entrypoint(&self, param_context: &mut ParamContext) -> Result<String, String> {
        let quoted_block_name = rand_block_name();
        let quoted_schema = quote_ident(&self.table.schema);
        let quoted_table = quote_ident(&self.table.name);
        let object_clause = self.to_sql(&quoted_block_name, param_context)?;

        if self.node_id.is_none() {
            return Err("Expected nodeId argument missing".to_string());
        }
        let node_id = self.node_id.as_ref().unwrap();

        let node_id_clause = node_id.to_sql(&quoted_block_name, &self.table, param_context)?;

        Ok(format!(
            "
            (
                select
                    {object_clause}
                from
                    {quoted_schema}.{quoted_table} as {quoted_block_name}
                where
                    {node_id_clause}
            )
            "
        ))
    }
}

impl NodeIdInstance {
    pub fn to_sql(
        &self,
        block_name: &str,
        table: &Table,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        // TODO: abstract this logical check into builder. It is not related to
        // transpiling and should not be in this module
        if (&self.schema_name, &self.table_name) != (&table.schema, &table.name) {
            return Err("nodeId belongs to a different collection".to_string());
        }

        let mut col_val_pairs: Vec<String> = vec![];
        for (col, val) in table.primary_key_columns().iter().zip(self.values.iter()) {
            let column_name = &col.name;
            let gson_val = json_to_gson(val)?;
            let val_clause = param_context.clause_for(&gson_val, &col.type_name)?;
            col_val_pairs.push(format!("{block_name}.{column_name} = {val_clause}"))
        }
        Ok(col_val_pairs.join(" and "))
    }
}

impl NodeSelection {
    pub fn to_sql(
        &self,
        block_name: &str,
        param_context: &mut ParamContext,
    ) -> Result<String, String> {
        Ok(match self {
            // TODO need to provide alias when called from node builder.
            Self::Connection(builder) => format!(
                "{}, {}",
                quote_literal(&builder.alias),
                builder.to_sql(Some(block_name), param_context)?
            ),
            Self::Node(builder) => format!(
                "{}, {}",
                quote_literal(&builder.alias),
                builder.to_relation_sql(block_name, param_context)?
            ),
            Self::Column(builder) => {
                let type_adjustment_clause = match builder.column.type_oid {
                    20 => "::text",           // bigints as text
                    114 | 3802 => "#>> '{}'", // json/b as stringified
                    1700 => "::text",         // numeric as text
                    _ => "",
                };

                format!(
                    "{}, {}{}",
                    quote_literal(&builder.alias),
                    builder.to_sql(block_name)?,
                    type_adjustment_clause
                )
            }
            Self::Function(builder) => format!(
                "{}, {}",
                quote_literal(&builder.alias),
                builder.to_sql(block_name)?
            ),
            Self::NodeId(builder) => format!(
                "{}, {}",
                quote_literal(&builder.alias),
                builder.to_sql(block_name)?
            ),
            Self::Typename { alias, typename } => {
                format!("{}, {}", quote_literal(alias), quote_literal(typename))
            }
        })
    }
}

impl ColumnBuilder {
    pub fn to_sql(&self, block_name: &str) -> Result<String, String> {
        Ok(format!(
            "{}.{}",
            &block_name,
            quote_ident(&self.column.name)
        ))
    }
}

impl NodeIdBuilder {
    pub fn to_sql(&self, block_name: &str) -> Result<String, String> {
        let column_selects: Vec<String> = self
            .columns
            .iter()
            .map(|col| format!("{}.{}", block_name, col.name))
            .collect();
        let column_clause = column_selects.join(", ");
        let schema_name = quote_literal(&self.schema_name);
        let table_name = quote_literal(&self.table_name);
        Ok(format!(
            "translate(encode(convert_to(jsonb_build_array({schema_name}, {table_name}, {column_clause})::text, 'utf-8'), 'base64'), E'\n', '')"
        ))
    }
}

impl FunctionBuilder {
    pub fn to_sql(&self, block_name: &str) -> Result<String, String> {
        let schema_name = &self.function.schema_name;
        let function_name = &self.function.name;
        Ok(format!("{schema_name}.{function_name}({block_name})"))
    }
}

impl Serialize for __FieldBuilder {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut map = serializer.serialize_map(Some(self.selections.len()))?;

        for selection in &self.selections {
            match &selection.selection {
                __FieldField::Name => {
                    map.serialize_entry(&selection.alias, &self.field.name())?;
                }
                __FieldField::Description => {
                    map.serialize_entry(&selection.alias, &self.field.description())?;
                }

                __FieldField::IsDeprecated => {
                    map.serialize_entry(&selection.alias, &self.field.is_deprecated())?;
                }
                __FieldField::DeprecationReason => {
                    map.serialize_entry(&selection.alias, &self.field.deprecation_reason())?;
                }
                __FieldField::Arguments(input_value_builders) => {
                    map.serialize_entry(&selection.alias, input_value_builders)?;
                }
                __FieldField::Type(t) => {
                    // TODO
                    map.serialize_entry(&selection.alias, t)?;
                }
                __FieldField::Typename { alias, typename } => {
                    map.serialize_entry(&alias, typename)?;
                }
            }
        }
        map.end()
    }
}

impl Serialize for __TypeBuilder {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut map = serializer.serialize_map(Some(self.selections.len()))?;

        for selection in &self.selections {
            match &selection.selection {
                __TypeField::Kind => {
                    map.serialize_entry(&selection.alias, &format!("{:?}", self.type_.kind()))?;
                }
                __TypeField::Name => {
                    map.serialize_entry(&selection.alias, &self.type_.name())?;
                }
                __TypeField::Description => {
                    map.serialize_entry(&selection.alias, &self.type_.description())?;
                }
                __TypeField::Fields(fields) => {
                    map.serialize_entry(&selection.alias, fields)?;
                }
                __TypeField::InputFields(input_field_builders) => {
                    map.serialize_entry(&selection.alias, input_field_builders)?;
                }
                __TypeField::Interfaces(interfaces) => {
                    map.serialize_entry(&selection.alias, &interfaces)?;
                }
                __TypeField::EnumValues(enum_values) => {
                    map.serialize_entry(&selection.alias, enum_values)?;
                }
                __TypeField::PossibleTypes(possible_types) => {
                    map.serialize_entry(&selection.alias, &possible_types)?;
                }
                __TypeField::OfType(t_builder) => {
                    map.serialize_entry(&selection.alias, t_builder)?;
                }
                __TypeField::Typename { alias, typename } => {
                    map.serialize_entry(&alias, typename)?;
                }
            }
        }
        map.end()
    }
}

impl Serialize for __SchemaBuilder {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut map = serializer.serialize_map(Some(self.selections.len()))?;

        for selection in &self.selections {
            match &selection.selection {
                __SchemaField::Types(type_builders) => {
                    map.serialize_entry(&selection.alias, &type_builders)?;
                }
                __SchemaField::QueryType(type_builder) => {
                    map.serialize_entry(&selection.alias, &type_builder)?;
                }
                __SchemaField::MutationType(type_builder) => {
                    map.serialize_entry(&selection.alias, &type_builder)?;
                }
                __SchemaField::SubscriptionType(type_builder) => {
                    map.serialize_entry(&selection.alias, &type_builder)?;
                }
                __SchemaField::Directives => {
                    let x: Vec<bool> = vec![];
                    map.serialize_entry(&selection.alias, &x)?;
                }
                __SchemaField::Typename { alias, typename } => {
                    map.serialize_entry(&alias, typename)?;
                }
            }
        }
        map.end()
    }
}

impl Serialize for __InputValueBuilder {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut map = serializer.serialize_map(Some(self.selections.len()))?;

        for selection in &self.selections {
            match &selection.selection {
                __InputValueField::Name => {
                    map.serialize_entry(&selection.alias, &self.input_value.name())?;
                }
                __InputValueField::Description => {
                    map.serialize_entry(&selection.alias, &self.input_value.description())?;
                }
                __InputValueField::Type(type_builder) => {
                    map.serialize_entry(&selection.alias, &type_builder)?;
                }
                __InputValueField::DefaultValue => {
                    map.serialize_entry(&selection.alias, &self.input_value.default_value())?;
                }
                __InputValueField::IsDeprecated => {
                    map.serialize_entry(&selection.alias, &self.input_value.is_deprecated())?;
                }
                __InputValueField::DeprecationReason => {
                    map.serialize_entry(&selection.alias, &self.input_value.deprecation_reason())?;
                }
                __InputValueField::Typename { alias, typename } => {
                    map.serialize_entry(&alias, typename)?;
                }
            }
        }
        map.end()
    }
}

impl Serialize for __EnumValueBuilder {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut map = serializer.serialize_map(Some(self.selections.len()))?;

        for selection in &self.selections {
            match &selection.selection {
                __EnumValueField::Name => {
                    map.serialize_entry(&selection.alias, &self.enum_value.name())?;
                }
                __EnumValueField::Description => {
                    map.serialize_entry(&selection.alias, &self.enum_value.description())?;
                }
                __EnumValueField::IsDeprecated => {
                    map.serialize_entry(&selection.alias, &self.enum_value.is_deprecated())?;
                }
                __EnumValueField::DeprecationReason => {
                    map.serialize_entry(&selection.alias, &self.enum_value.deprecation_reason())?;
                }
                __EnumValueField::Typename { alias, typename } => {
                    map.serialize_entry(&alias, typename)?;
                }
            }
        }
        map.end()
    }
}

#[cfg(any(test, feature = "pg_test"))]
#[pgx::pg_schema]
mod tests {
    use crate::transpile::*;

    #[pg_test]
    fn test_quote_ident() {
        let res = quote_ident("hello world");
        assert_eq!(res, r#""hello world""#);
    }

    #[pg_test]
    fn test_quote_literal() {
        let res = quote_ident("hel'lo world");
        assert_eq!(res, r#""hel'lo world""#);
    }
}
