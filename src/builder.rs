use crate::graphql::*;
use crate::gson;
use crate::parser_util::*;
use crate::sql_types::*;
use graphql_parser::query::*;
use serde::Serialize;
use std::collections::HashMap;
use std::hash::Hash;
use std::ops::Deref;
use std::str::FromStr;
use std::sync::Arc;

#[derive(Clone, Debug)]
pub struct AggregateBuilder {
    pub alias: String,
    pub selections: Vec<AggregateSelection>,
}

#[derive(Clone, Debug)]
pub enum AggregateSelection {
    Count {
        alias: String,
    },
    Sum {
        alias: String,
        column_builders: Vec<ColumnBuilder>,
    },
    Avg {
        alias: String,
        column_builders: Vec<ColumnBuilder>,
    },
    Min {
        alias: String,
        column_builders: Vec<ColumnBuilder>,
    },
    Max {
        alias: String,
        column_builders: Vec<ColumnBuilder>,
    },
    Typename {
        alias: String,
        typename: String,
    },
}

#[derive(Clone, Debug)]
pub struct InsertBuilder {
    // args
    pub objects: Vec<InsertRowBuilder>,

    // metadata
    pub table: Arc<Table>,

    //fields
    pub selections: Vec<InsertSelection>,
}

#[derive(Clone, Debug)]
pub struct InsertRowBuilder {
    // String is Column name
    pub row: HashMap<String, InsertElemValue>,
}

#[derive(Clone, Debug)]
pub enum InsertElemValue {
    Default, // Equivalent to gson::Absent
    Value(serde_json::Value),
}

#[allow(clippy::large_enum_variant)]
#[derive(Clone, Debug)]
pub enum InsertSelection {
    AffectedCount { alias: String },
    Records(NodeBuilder),
    Typename { alias: String, typename: String },
}

fn read_argument<'a, T>(
    arg_name: &str,
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<gson::Value, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let input_value: __InputValue = match field.get_arg(arg_name) {
        Some(arg) => arg,
        None => return Err(format!("Internal error 1: {}", arg_name)),
    };

    let user_input: Option<&graphql_parser::query::Value<'a, T>> = query_field
        .arguments
        .iter()
        .filter(|(input_arg_name, _)| input_arg_name.as_ref() == arg_name)
        .map(|(_, v)| v)
        .next();

    let user_json_unvalidated = match user_input {
        None => gson::Value::Absent,
        Some(val) => to_gson(val, variables, variable_definitions)?,
    };

    let user_json_validated = validate_arg_from_type(&input_value.type_(), &user_json_unvalidated)?;
    Ok(user_json_validated)
}

fn read_argument_at_most<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<i64, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let at_most: gson::Value = read_argument(
        "atMost",
        field,
        query_field,
        variables,
        variable_definitions,
    )
    .unwrap_or(gson::Value::Number(gson::Number::Integer(1)));
    match at_most {
        gson::Value::Number(gson::Number::Integer(x)) => Ok(x),
        _ => Err("Internal Error: failed to parse validated atFirst".to_string()),
    }
}

fn parse_node_id(encoded: gson::Value) -> Result<NodeIdInstance, String> {
    extern crate base64;
    use std::str;

    let node_id_base64_encoded_string: String = match encoded {
        gson::Value::String(s) => s,
        _ => return Err("Invalid value passed to nodeId argument, Error 1".to_string()),
    };

    let node_id_json_string_utf8: Vec<u8> = base64::decode(node_id_base64_encoded_string)
        .map_err(|_| "Invalid value passed to nodeId argument. Error 2".to_string())?;

    let node_id_json_string: &str = str::from_utf8(&node_id_json_string_utf8)
        .map_err(|_| "Invalid value passed to nodeId argument. Error 3".to_string())?;

    let node_id_json: serde_json::Value = serde_json::from_str(node_id_json_string)
        .map_err(|_| "Invalid value passed to nodeId argument. Error 4".to_string())?;

    match node_id_json {
        serde_json::Value::Array(x_arr) => {
            if x_arr.len() < 3 {
                return Err("Invalid value passed to nodeId argument. Error 5".to_string());
            }

            let mut x_arr_iter = x_arr.into_iter();
            let schema_name = match x_arr_iter
                .next()
                .expect("failed to get schema name from nodeId argument")
            {
                serde_json::Value::String(s) => s,
                _ => {
                    return Err("Invalid value passed to nodeId argument. Error 6".to_string());
                }
            };

            let table_name = match x_arr_iter
                .next()
                .expect("failed to get table name from nodeId argument")
            {
                serde_json::Value::String(s) => s,
                _ => {
                    return Err("Invalid value passed to nodeId argument. Error 7".to_string());
                }
            };
            let values: Vec<serde_json::Value> = x_arr_iter.collect();

            // Popuate a NodeIdInstance
            Ok(NodeIdInstance {
                schema_name,
                table_name,
                values,
            })
        }
        _ => Err("Invalid value passed to nodeId argument. Error 10".to_string()),
    }
}

fn read_argument_node_id<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<NodeIdInstance, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    // nodeId is a base64 encoded string of [schema, table, pkey_val1, pkey_val2, ...]
    let node_id_base64_encoded_json_string: gson::Value = read_argument(
        "nodeId",
        field,
        query_field,
        variables,
        variable_definitions,
    )?;

    parse_node_id(node_id_base64_encoded_json_string)
}

fn read_argument_objects<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<Vec<InsertRowBuilder>, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    // [{"name": "bob", "email": "a@b.com"}, {..}]
    let validated: gson::Value = read_argument(
        "objects",
        field,
        query_field,
        variables,
        variable_definitions,
    )?;

    // [<Table>OrderBy!]
    let insert_type: InsertInputType = match field
        .get_arg("objects")
        .expect("failed to get `objects` argument")
        .type_()
        .unmodified_type()
    {
        __Type::InsertInput(insert_type) => insert_type,
        _ => return Err("Could not locate Insert Entity type".to_string()),
    };

    let mut objects: Vec<InsertRowBuilder> = vec![];

    let insert_type_field_map = input_field_map(&__Type::InsertInput(insert_type));

    // validated user input kv map
    match validated {
        gson::Value::Absent | gson::Value::Null => (),
        gson::Value::Array(x_arr) => {
            for row in x_arr.iter() {
                let mut column_elems: HashMap<String, InsertElemValue> = HashMap::new();

                match row {
                    gson::Value::Absent | gson::Value::Null => continue,
                    gson::Value::Object(obj) => {
                        for (column_field_name, col_input_value) in obj.iter() {
                            let column_input_value: &__InputValue =
                                match insert_type_field_map.get(column_field_name) {
                                    Some(input_field) => input_field,
                                    None => return Err("Insert re-validation error 3".to_string()),
                                };

                            match &column_input_value.sql_type {
                                Some(NodeSQLType::Column(col)) => {
                                    let insert_col_builder = match col_input_value {
                                        gson::Value::Absent => InsertElemValue::Default,
                                        _ => InsertElemValue::Value(gson::gson_to_json(
                                            col_input_value,
                                        )?),
                                    };
                                    column_elems.insert(col.name.clone(), insert_col_builder);
                                }
                                _ => return Err("Insert re-validation error 4".to_string()),
                            }
                        }
                    }
                    _ => return Err("Insert re-validation errror 1".to_string()),
                }

                let insert_row_builder = InsertRowBuilder { row: column_elems };
                objects.push(insert_row_builder);
            }
        }
        _ => return Err("Insert re-validation errror".to_string()),
    };

    if objects.is_empty() {
        return Err("At least one record must be provided to objects".to_string());
    }
    Ok(objects)
}

pub fn to_insert_builder<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<InsertBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();
    let type_name = type_
        .name()
        .ok_or("Encountered type without name in connection builder")?;
    let field_map = field_map(&type_);

    match &type_ {
        __Type::InsertResponse(xtype) => {
            // Raise for disallowed arguments
            restrict_allowed_arguments(&["objects"], query_field)?;

            let objects: Vec<InsertRowBuilder> =
                read_argument_objects(field, query_field, variables, variable_definitions)?;

            let mut builder_fields: Vec<InsertSelection> = vec![];

            let selection_fields = normalize_selection_set(
                &query_field.selection_set,
                fragment_definitions,
                &type_name,
                variables,
            )?;

            for selection_field in selection_fields {
                match field_map.get(selection_field.name.as_ref()) {
                    None => return Err("unknown field in insert".to_string()),
                    Some(f) => builder_fields.push(match f.name().as_ref() {
                        "affectedCount" => InsertSelection::AffectedCount {
                            alias: alias_or_name(&selection_field),
                        },
                        "records" => {
                            let node_builder = to_node_builder(
                                f,
                                &selection_field,
                                fragment_definitions,
                                variables,
                                &[],
                                variable_definitions,
                            );
                            InsertSelection::Records(node_builder?)
                        }
                        "__typename" => InsertSelection::Typename {
                            alias: alias_or_name(&selection_field),
                            typename: xtype
                                .name()
                                .expect("insert response type should have a name"),
                        },
                        _ => return Err("unexpected field type on insert response".to_string()),
                    }),
                }
            }
            Ok(InsertBuilder {
                table: Arc::clone(&xtype.table),
                objects,
                selections: builder_fields,
            })
        }
        _ => Err(format!(
            "can not build query for non-insert type {:?}",
            type_.name()
        )),
    }
}

#[derive(Clone, Debug)]
pub struct UpdateBuilder {
    // args
    pub filter: FilterBuilder,
    pub set: SetBuilder,
    pub at_most: i64,

    // metadata
    pub table: Arc<Table>,

    //fields
    pub selections: Vec<UpdateSelection>,
}

#[derive(Clone, Debug)]
pub struct SetBuilder {
    // String is Column name
    pub set: HashMap<String, serde_json::Value>,
}

#[allow(clippy::large_enum_variant)]
#[derive(Clone, Debug)]
pub enum UpdateSelection {
    AffectedCount { alias: String },
    Records(NodeBuilder),
    Typename { alias: String, typename: String },
}

fn read_argument_set<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<SetBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let validated: gson::Value =
        read_argument("set", field, query_field, variables, variable_definitions)?;

    let update_type: UpdateInputType = match field
        .get_arg("set")
        .expect("failed to get `set` argument")
        .type_()
        .unmodified_type()
    {
        __Type::UpdateInput(type_) => type_,
        _ => return Err("Could not locate update entity type".to_string()),
    };

    let mut set: HashMap<String, serde_json::Value> = HashMap::new();

    let update_type_field_map = input_field_map(&__Type::UpdateInput(update_type));

    // validated user input kv map
    match validated {
        gson::Value::Absent | gson::Value::Null => (),
        gson::Value::Object(obj) => {
            for (column_field_name, col_input_value) in obj.iter() {
                // If value is absent, skip it. Nulls are handled as literals
                if col_input_value == &gson::Value::Absent {
                    continue;
                }
                let column_input_value: &__InputValue =
                    match update_type_field_map.get(column_field_name) {
                        Some(input_field) => input_field,
                        None => return Err("Update re-validation error 3".to_string()),
                    };

                match &column_input_value.sql_type {
                    Some(NodeSQLType::Column(col)) => {
                        set.insert(col.name.clone(), gson::gson_to_json(col_input_value)?);
                    }
                    _ => return Err("Update re-validation error 4".to_string()),
                }
            }
        }
        _ => return Err("Update re-validation errror".to_string()),
    };

    if set.is_empty() {
        return Err("At least one mapping must be provided to set argument".to_string());
    }

    Ok(SetBuilder { set })
}

pub fn to_update_builder<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<UpdateBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();
    let type_name = type_
        .name()
        .ok_or("Encountered type without name in update builder")?;
    let field_map = field_map(&type_);

    match &type_ {
        __Type::UpdateResponse(xtype) => {
            // Raise for disallowed arguments
            restrict_allowed_arguments(&["set", "filter", "atMost"], query_field)?;

            let set: SetBuilder =
                read_argument_set(field, query_field, variables, variable_definitions)?;
            let filter: FilterBuilder =
                read_argument_filter(field, query_field, variables, variable_definitions)?;
            let at_most: i64 =
                read_argument_at_most(field, query_field, variables, variable_definitions)?;

            let mut builder_fields: Vec<UpdateSelection> = vec![];

            let selection_fields = normalize_selection_set(
                &query_field.selection_set,
                fragment_definitions,
                &type_name,
                variables,
            )?;

            for selection_field in selection_fields {
                match field_map.get(selection_field.name.as_ref()) {
                    None => return Err("unknown field in update".to_string()),
                    Some(f) => builder_fields.push(match f.name().as_ref() {
                        "affectedCount" => UpdateSelection::AffectedCount {
                            alias: alias_or_name(&selection_field),
                        },
                        "records" => {
                            let node_builder = to_node_builder(
                                f,
                                &selection_field,
                                fragment_definitions,
                                variables,
                                &[],
                                variable_definitions,
                            );
                            UpdateSelection::Records(node_builder?)
                        }
                        "__typename" => UpdateSelection::Typename {
                            alias: alias_or_name(&selection_field),
                            typename: xtype
                                .name()
                                .expect("update response type should have a name"),
                        },
                        _ => return Err("unexpected field type on update response".to_string()),
                    }),
                }
            }
            Ok(UpdateBuilder {
                filter,
                set,
                at_most,
                table: Arc::clone(&xtype.table),
                selections: builder_fields,
            })
        }
        _ => Err(format!(
            "can not build query for non-update type {:?}",
            type_.name()
        )),
    }
}

#[derive(Clone, Debug)]
pub struct DeleteBuilder {
    // args
    pub filter: FilterBuilder,
    pub at_most: i64,

    // metadata
    pub table: Arc<Table>,

    //fields
    pub selections: Vec<DeleteSelection>,
}

#[allow(clippy::large_enum_variant)]
#[derive(Clone, Debug)]
pub enum DeleteSelection {
    AffectedCount { alias: String },
    Records(NodeBuilder),
    Typename { alias: String, typename: String },
}

pub fn to_delete_builder<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<DeleteBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();
    let type_name = type_
        .name()
        .ok_or("Encountered type without name in delete builder")?;
    let field_map = field_map(&type_);

    match &type_ {
        __Type::DeleteResponse(xtype) => {
            // Raise for disallowed arguments
            restrict_allowed_arguments(&["filter", "atMost"], query_field)?;

            let filter: FilterBuilder =
                read_argument_filter(field, query_field, variables, variable_definitions)?;
            let at_most: i64 =
                read_argument_at_most(field, query_field, variables, variable_definitions)?;

            let mut builder_fields: Vec<DeleteSelection> = vec![];

            let selection_fields = normalize_selection_set(
                &query_field.selection_set,
                fragment_definitions,
                &type_name,
                variables,
            )?;

            for selection_field in selection_fields {
                match field_map.get(selection_field.name.as_ref()) {
                    None => return Err("unknown field in delete".to_string()),
                    Some(f) => builder_fields.push(match f.name().as_ref() {
                        "affectedCount" => DeleteSelection::AffectedCount {
                            alias: alias_or_name(&selection_field),
                        },
                        "records" => {
                            let node_builder = to_node_builder(
                                f,
                                &selection_field,
                                fragment_definitions,
                                variables,
                                &[],
                                variable_definitions,
                            );
                            DeleteSelection::Records(node_builder?)
                        }
                        "__typename" => DeleteSelection::Typename {
                            alias: alias_or_name(&selection_field),
                            typename: xtype
                                .name()
                                .expect("delete response type should have a name"),
                        },
                        _ => return Err("unexpected field type on delete response".to_string()),
                    }),
                }
            }
            Ok(DeleteBuilder {
                filter,
                at_most,
                table: Arc::clone(&xtype.table),
                selections: builder_fields,
            })
        }
        _ => Err(format!(
            "can not build query for non-delete type {:?}",
            type_.name()
        )),
    }
}

pub struct FunctionCallBuilder {
    // metadata
    pub function: Arc<Function>,

    // args
    pub args_builder: FuncCallArgsBuilder,

    pub return_type_builder: FuncCallReturnTypeBuilder,
}

pub enum FuncCallReturnTypeBuilder {
    Scalar,
    List,
    Node(NodeBuilder),
    Connection(ConnectionBuilder),
}

#[derive(Clone, Debug)]
pub struct FuncCallArgsBuilder {
    pub args: Vec<(Option<FuncCallSqlArgName>, serde_json::Value)>,
}

#[derive(Clone, Debug)]
pub struct FuncCallSqlArgName {
    pub type_name: String,
    pub name: String,
}

pub fn to_function_call_builder<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<FunctionCallBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();

    match &type_ {
        __Type::FuncCallResponse(func_call_resp_type) => {
            let args = field.args();
            let allowed_args: Vec<&str> = args.iter().map(|a| a.name_.as_str()).collect();
            restrict_allowed_arguments(&allowed_args, query_field)?;
            let args = read_func_call_args(
                field,
                query_field,
                variables,
                func_call_resp_type,
                variable_definitions,
            )?;

            let return_type_builder = match func_call_resp_type.return_type.deref() {
                __Type::Scalar(_) => FuncCallReturnTypeBuilder::Scalar,
                __Type::List(_) => FuncCallReturnTypeBuilder::List,
                __Type::Node(_) => {
                    let node_builder = to_node_builder(
                        field,
                        query_field,
                        fragment_definitions,
                        variables,
                        &allowed_args,
                        variable_definitions,
                    )?;
                    FuncCallReturnTypeBuilder::Node(node_builder)
                }
                __Type::Connection(_) => {
                    let connection_builder = to_connection_builder(
                        field,
                        query_field,
                        fragment_definitions,
                        variables,
                        &allowed_args,
                        variable_definitions,
                    )?;
                    FuncCallReturnTypeBuilder::Connection(connection_builder)
                }
                _ => {
                    return Err(format!(
                        "unsupported return type: {}",
                        func_call_resp_type
                            .return_type
                            .unmodified_type()
                            .name()
                            .ok_or("Encountered type without name in function call builder")?
                    ));
                }
            };

            Ok(FunctionCallBuilder {
                function: Arc::clone(&func_call_resp_type.function),
                args_builder: args,
                return_type_builder,
            })
        }
        _ => Err(format!(
            "can not build query for non-function type {:?}",
            type_.name()
        )),
    }
}

fn read_func_call_args<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    variables: &serde_json::Value,
    func_call_resp_type: &FuncCallResponseType,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<FuncCallArgsBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let inflected_to_sql_args = func_call_resp_type.inflected_to_sql_args();
    let mut args = vec![];
    for arg in field.args() {
        let arg_value = read_argument(
            &arg.name(),
            field,
            query_field,
            variables,
            variable_definitions,
        )?;
        if !arg_value.is_absent() {
            let func_call_sql_arg_name =
                inflected_to_sql_args
                    .get(&arg.name())
                    .map(|(type_name, name)| FuncCallSqlArgName {
                        type_name: type_name.clone(),
                        name: name.clone(),
                    });
            args.push((func_call_sql_arg_name, gson::gson_to_json(&arg_value)?));
        };
    }
    Ok(FuncCallArgsBuilder { args })
}

#[derive(Clone, Debug)]
pub struct ConnectionBuilderSource {
    pub table: Arc<Table>,
    pub fkey: Option<ForeignKeyReversible>,
}

#[derive(Clone, Debug)]
pub struct ConnectionBuilder {
    pub alias: String,

    // args
    pub first: Option<u64>,
    pub last: Option<u64>,
    pub before: Option<Cursor>,
    pub after: Option<Cursor>,
    pub offset: Option<u64>,
    pub filter: FilterBuilder,
    pub order_by: OrderByBuilder,

    // metadata
    pub source: ConnectionBuilderSource,

    //fields
    pub selections: Vec<ConnectionSelection>,
    pub max_rows: u64,
}

#[derive(Clone, Debug)]
pub enum CompoundFilterBuilder {
    And(Vec<FilterBuilderElem>),
    Or(Vec<FilterBuilderElem>),
    Not(FilterBuilderElem),
}

#[derive(Clone, Debug)]
pub enum FilterBuilderElem {
    Column {
        column: Arc<Column>,
        op: FilterOp,
        value: serde_json::Value, //String, // string repr castable by postgres
    },
    NodeId(NodeIdInstance),
    Compound(Box<CompoundFilterBuilder>),
}

#[derive(Clone, Debug)]
pub struct FilterBuilder {
    pub elems: Vec<FilterBuilderElem>,
}

#[derive(Clone, Debug)]
pub enum OrderDirection {
    AscNullsFirst,
    AscNullsLast,
    DescNullsFirst,
    DescNullsLast,
}

impl OrderDirection {
    pub fn nulls_first(&self) -> bool {
        match self {
            Self::AscNullsFirst => true,
            Self::AscNullsLast => false,
            Self::DescNullsFirst => true,
            Self::DescNullsLast => false,
        }
    }

    pub fn is_asc(&self) -> bool {
        match self {
            Self::AscNullsFirst => true,
            Self::AscNullsLast => true,
            Self::DescNullsFirst => false,
            Self::DescNullsLast => false,
        }
    }
}

impl FromStr for OrderDirection {
    type Err = String;

    fn from_str(input: &str) -> Result<Self, Self::Err> {
        match input {
            "AscNullsFirst" => Ok(Self::AscNullsFirst),
            "AscNullsLast" => Ok(Self::AscNullsLast),
            "DescNullsFirst" => Ok(Self::DescNullsFirst),
            "DescNullsLast" => Ok(Self::DescNullsLast),
            _ => Err(format!("Invalid order operation {}", input)),
        }
    }
}
impl OrderDirection {
    pub fn reverse(&self) -> Self {
        match self {
            Self::AscNullsFirst => Self::DescNullsLast,
            Self::AscNullsLast => Self::DescNullsFirst,
            Self::DescNullsFirst => Self::AscNullsLast,
            Self::DescNullsLast => Self::AscNullsFirst,
        }
    }
}

impl OrderByBuilderElem {
    fn reverse(&self) -> Self {
        Self {
            column: Arc::clone(&self.column),
            direction: self.direction.reverse(),
        }
    }
}

impl OrderByBuilder {
    pub fn reverse(&self) -> Self {
        Self {
            elems: self.elems.iter().map(|x| x.reverse()).collect(),
        }
    }
}

#[derive(Clone, Debug)]
pub struct CursorElement {
    pub value: serde_json::Value,
}
#[derive(Clone, Debug)]
pub struct Cursor {
    pub elems: Vec<CursorElement>,
}

impl FromStr for Cursor {
    type Err = String;

    fn from_str(input: &str) -> Result<Self, Self::Err> {
        extern crate base64;
        use std::str;

        match base64::decode(input) {
            Ok(vec_u8) => match str::from_utf8(&vec_u8) {
                Ok(v) => {
                    let mut elems: Vec<CursorElement> = vec![];
                    match serde_json::from_str(v) {
                        Ok(json) => match json {
                            serde_json::Value::Array(x_arr) => {
                                for x in &x_arr {
                                    let element = CursorElement { value: x.clone() };
                                    elems.push(element);
                                }
                                Ok(Cursor { elems })
                            }
                            _ => Err("Failed to decode cursor, error 4".to_string()),
                        },
                        Err(_) => Err("Failed to decode cursor, error 3".to_string()),
                    }
                }
                Err(_) => Err("Failed to decode cursor, error 2".to_string()),
            },
            Err(_) => Err("Failed to decode cursor, error 1".to_string()),
        }
    }
}

#[derive(Clone, Debug)]
pub struct OrderByBuilderElem {
    pub column: Arc<Column>,
    pub direction: OrderDirection,
}

#[derive(Clone, Debug)]
pub struct OrderByBuilder {
    pub elems: Vec<OrderByBuilderElem>,
}

#[derive(Clone, Debug)]
pub struct PageInfoBuilder {
    pub alias: String,
    pub selections: Vec<PageInfoSelection>,
}

#[derive(Clone, Debug)]
pub enum PageInfoSelection {
    StartCursor { alias: String },
    EndCursor { alias: String },
    HasNextPage { alias: String },
    HasPreviousPage { alias: String },
    Typename { alias: String, typename: String },
}

#[derive(Clone, Debug)]
pub enum ConnectionSelection {
    TotalCount { alias: String },
    Edge(EdgeBuilder),
    PageInfo(PageInfoBuilder),
    Typename { alias: String, typename: String },
    Aggregate(AggregateBuilder),
}

#[derive(Clone, Debug)]
pub struct EdgeBuilder {
    pub alias: String,
    pub selections: Vec<EdgeSelection>,
}

#[allow(clippy::large_enum_variant)]
#[derive(Clone, Debug)]
pub enum EdgeSelection {
    Cursor { alias: String },
    Node(NodeBuilder),
    Typename { alias: String, typename: String },
}

#[derive(Clone, Debug)]
pub struct NodeBuilder {
    // args
    pub node_id: Option<NodeIdInstance>,

    pub alias: String,

    // metadata
    pub table: Arc<Table>,
    pub fkey: Option<Arc<ForeignKey>>,
    pub reverse_reference: Option<bool>,

    pub selections: Vec<NodeSelection>,
}

#[derive(Clone, Debug)]
pub enum NodeSelection {
    Connection(ConnectionBuilder),
    Node(NodeBuilder),
    Column(ColumnBuilder),
    Function(FunctionBuilder),
    NodeId(NodeIdBuilder),
    Typename { alias: String, typename: String },
}

#[derive(Clone, Debug)]
pub struct NodeIdInstance {
    pub schema_name: String,
    pub table_name: String,
    // Vec matching length of "columns" representing primary key values
    pub values: Vec<serde_json::Value>,
}

#[derive(Clone, Debug)]
pub struct NodeIdBuilder {
    pub alias: String,
    pub schema_name: String,
    pub table_name: String,
    pub columns: Vec<Arc<Column>>,
}

#[derive(Clone, Debug)]
pub struct ColumnBuilder {
    pub alias: String,
    pub column: Arc<Column>,
}

#[derive(Clone, Debug)]
pub struct FunctionBuilder {
    pub alias: String,
    pub function: Arc<Function>,
    pub table: Arc<Table>,
    pub selection: FunctionSelection,
}

#[derive(Clone, Debug)]
pub enum FunctionSelection {
    ScalarSelf,
    Array, // To suport non-scalars this will require an inner type
    Connection(ConnectionBuilder),
    Node(NodeBuilder),
}

fn restrict_allowed_arguments<'a, T>(
    arg_names: &[&str],
    query_field: &graphql_parser::query::Field<'a, T>,
) -> Result<(), String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let extra_keys: Vec<&str> = query_field
        .arguments
        .iter()
        .filter(|(input_arg_name, _)| !arg_names.contains(&input_arg_name.as_ref()))
        .map(|(name, _)| name.as_ref())
        .collect();

    match !extra_keys.is_empty() {
        true => Err(format!("Input contains extra keys {:?}", extra_keys)),
        false => Ok(()),
    }
}

/// Reads the "filter" argument
fn read_argument_filter<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<FilterBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let validated: gson::Value = read_argument(
        "filter",
        field,
        query_field,
        variables,
        variable_definitions,
    )?;

    let filter_type = field
        .get_arg("filter")
        .expect("failed to get filter argument")
        .type_()
        .unmodified_type();
    if !matches!(filter_type, __Type::FilterEntity(_)) {
        return Err("Could not locate Filter Entity type".to_string());
    }

    let filter_field_map = input_field_map(&filter_type);

    let filters = create_filters(&validated, &filter_field_map)?;

    Ok(FilterBuilder { elems: filters })
}

fn create_filters(
    validated: &gson::Value,
    filter_field_map: &HashMap<String, __InputValue>,
) -> Result<Vec<FilterBuilderElem>, String> {
    let mut filters = vec![];
    // validated user input kv map
    let kv_map = match validated {
        gson::Value::Absent | gson::Value::Null => return Ok(filters),
        gson::Value::Object(kv) => kv,
        _ => return Err("Filter re-validation error".to_string()),
    };

    for (k, op_to_v) in kv_map {
        // k = str, v = {"eq": 1}
        let filter_iv: &__InputValue = match filter_field_map.get(k) {
            Some(filter_iv) => filter_iv,
            None => return Err("Filter re-validation error in filter_iv".to_string()),
        };

        match op_to_v {
            gson::Value::Absent | gson::Value::Null => continue,
            gson::Value::Object(filter_op_to_value_map) => {
                // key `not` can either be a compound filter or a column. We can find out which it is by
                // checking its type. If it is a `not` filter then its type will be __Type::FilterEntity(_)
                // else its type will be __Type::FilterType(_). Refer to the the method
                // crate::graphql::FilterEntityType::input_fields() method for details.
                let is_a_not_filter_type = matches!(filter_iv.type_(), __Type::FilterEntity(_));
                if k == NOT_FILTER_NAME && is_a_not_filter_type {
                    if let gson::Value::Object(_) = op_to_v {
                        let inner_filters = create_filters(op_to_v, filter_field_map)?;
                        // If there are no inner filters we avoid creating an argumentless `not` expression. i.e. avoid `not()`
                        if !inner_filters.is_empty() {
                            // Multiple inner filters are implicitly `and`ed together
                            let inner_filter = FilterBuilderElem::Compound(Box::new(
                                CompoundFilterBuilder::And(inner_filters),
                            ));
                            let filter = FilterBuilderElem::Compound(Box::new(
                                CompoundFilterBuilder::Not(inner_filter),
                            ));
                            filters.push(filter);
                        }
                    } else {
                        return Err("Invalid `not` filter".to_string());
                    }
                } else {
                    for (filter_op_str, filter_val) in filter_op_to_value_map {
                        let filter_op = FilterOp::from_str(filter_op_str)?;

                        // Skip absent
                        // Technically nulls should be treated as literals. It will always filter out all rows
                        // val <op> null is never true
                        if filter_val == &gson::Value::Absent {
                            continue;
                        }

                        let filter_builder =
                            create_filter_builder_elem(filter_iv, filter_op, filter_val)?;
                        filters.push(filter_builder);
                    }
                }
            }
            gson::Value::Array(values) if k == AND_FILTER_NAME || k == OR_FILTER_NAME => {
                // If there are no inner filters we avoid creating an argumentless `and`/`or` expression
                // which would have been anyways compiled away during transpilation
                if !values.is_empty() {
                    let mut compound_filters = Vec::with_capacity(values.len());
                    for value in values {
                        let inner_filters = create_filters(value, filter_field_map)?;
                        // Avoid argumentless `and`
                        if !inner_filters.is_empty() {
                            // Multiple inner filters are implicitly `and`ed together
                            let inner_filter = FilterBuilderElem::Compound(Box::new(
                                CompoundFilterBuilder::And(inner_filters),
                            ));
                            compound_filters.push(inner_filter);
                        }
                    }

                    let filter_builder = if k == AND_FILTER_NAME {
                        FilterBuilderElem::Compound(Box::new(CompoundFilterBuilder::And(
                            compound_filters,
                        )))
                    } else if k == OR_FILTER_NAME {
                        FilterBuilderElem::Compound(Box::new(CompoundFilterBuilder::Or(
                            compound_filters,
                        )))
                    } else {
                        return Err(
                            "Only `and` and `or` filters are allowed to take an array as input."
                                .to_string(),
                        );
                    };

                    filters.push(filter_builder);
                }
            }
            _ => return Err("Filter re-validation errror op_to_value map".to_string()),
        }
    }
    Ok(filters)
}

fn create_filter_builder_elem(
    filter_iv: &__InputValue,
    filter_op: FilterOp,
    filter_val: &gson::Value,
) -> Result<FilterBuilderElem, String> {
    Ok(match &filter_iv.sql_type {
        Some(NodeSQLType::Column(col)) => FilterBuilderElem::Column {
            column: Arc::clone(col),
            op: filter_op,
            value: gson::gson_to_json(filter_val)?,
        },
        Some(NodeSQLType::NodeId(_)) => {
            FilterBuilderElem::NodeId(parse_node_id(filter_val.clone())?)
        }
        _ => return Err("Filter type error, attempted filter on non-column".to_string()),
    })
}

/// Reads the "orderBy" argument. Auto-appends the primary key
fn read_argument_order_by<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<OrderByBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    // [{"id": "DescNullsLast"}]
    let validated: gson::Value = read_argument(
        "orderBy",
        field,
        query_field,
        variables,
        variable_definitions,
    )?;

    // [<Table>OrderBy!]
    let order_type: OrderByEntityType = match field
        .get_arg("orderBy")
        .expect("failed to get orderBy argument")
        .type_()
        .unmodified_type()
    {
        __Type::OrderByEntity(order_entity) => order_entity,
        _ => return Err("Could not locate OrderBy Entity type".to_string()),
    };

    let mut orders = vec![];

    let order_field_map = input_field_map(&__Type::OrderByEntity(order_type.clone()));

    // validated user input kv map
    match validated {
        gson::Value::Null | gson::Value::Absent => (),
        gson::Value::Array(x_arr) => {
            for elem in x_arr.iter() {
                // {"id", DescNullsLast}
                match elem {
                    gson::Value::Absent | gson::Value::Null => continue,
                    gson::Value::Object(obj) => {
                        for (column_field_name, order_direction_json) in obj.iter() {
                            let order_direction = match order_direction_json {
                                gson::Value::Absent | gson::Value::Null => continue,
                                gson::Value::String(x) => OrderDirection::from_str(x)?,
                                _ => return Err("Order re-validation error 6".to_string()),
                            };
                            let column_input_value: &__InputValue =
                                match order_field_map.get(column_field_name) {
                                    Some(input_field) => input_field,
                                    None => return Err("Order re-validation error 3".to_string()),
                                };

                            match &column_input_value.sql_type {
                                Some(NodeSQLType::Column(col)) => {
                                    let order_rec = OrderByBuilderElem {
                                        column: Arc::clone(col),
                                        direction: order_direction,
                                    };
                                    orders.push(order_rec);
                                }
                                _ => return Err("Order re-validation error 4".to_string()),
                            }
                        }
                    }
                    _ => return Err("OrderBy re-validation errror 1".to_string()),
                }
            }
        }
        _ => return Err("OrderBy re-validation errror".to_string()),
    };

    // To acheive consistent pagination, sorting should always include primary key
    let pkey = &order_type
        .table
        .primary_key()
        .ok_or_else(|| "Found table with no primary key".to_string())?;

    for col_name in &pkey.column_names {
        for col in &order_type.table.columns {
            if &col.name == col_name {
                let order_rec = OrderByBuilderElem {
                    column: Arc::clone(col),
                    direction: OrderDirection::AscNullsLast,
                };
                orders.push(order_rec);
                break;
            }
        }
    }
    Ok(OrderByBuilder { elems: orders })
}

/// Reads "before" and "after" cursor arguments
fn read_argument_cursor<'a, T>(
    arg_name: &str,
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<Option<Cursor>, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let validated: gson::Value = read_argument(
        arg_name,
        field,
        query_field,
        variables,
        variable_definitions,
    )?;
    let _: Scalar = match field
        .get_arg(arg_name)
        .unwrap_or_else(|| panic!("failed to get {} argument", arg_name))
        .type_()
        .unmodified_type()
    {
        __Type::Scalar(x) => x,
        _ => return Err(format!("Could not argument {}", arg_name)),
    };

    match validated {
        // Technically null should be treated as a literal here causing no result to return
        // however:
        // - there is no reason to ever intentionally pass a null literal to this argument
        // - alternate implementations treat null as absent for this argument
        // - passing null appears to be a common mistake
        // so for backwards compatibility and ease of use, we'll treat null literal as absent
        gson::Value::Absent | gson::Value::Null => Ok(None),
        gson::Value::String(x) => Ok(Some(Cursor::from_str(&x)?)),
        _ => Err("Cursor re-validation errror".to_string()),
    }
}

pub fn to_connection_builder<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
    extra_allowed_args: &[&str],
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<ConnectionBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();
    let type_ = type_.return_type();
    let type_name = type_
        .name()
        .ok_or("Encountered type without name in connection builder")?;
    let field_map = field_map(type_);
    let alias = alias_or_name(query_field);

    match &type_ {
        __Type::Connection(xtype) => {
            // Raise for disallowed arguments
            let mut allowed_args = vec![
                "first", "last", "before", "after", "offset", "filter", "orderBy",
            ];
            allowed_args.extend(extra_allowed_args);
            restrict_allowed_arguments(&allowed_args, query_field)?;

            // TODO: only one of first/last, before/after provided
            let first: gson::Value =
                read_argument("first", field, query_field, variables, variable_definitions)?;
            let first: Option<u64> = match first {
                gson::Value::Absent | gson::Value::Null => None,
                gson::Value::Number(gson::Number::Integer(n)) if n < 0 => {
                    return Err("`first` must be an unsigned integer".to_string())
                }
                gson::Value::Number(gson::Number::Integer(n)) => Some(n as u64),
                _ => {
                    return Err("Internal Error: failed to parse validated first".to_string());
                }
            };

            let last: gson::Value =
                read_argument("last", field, query_field, variables, variable_definitions)?;
            let last: Option<u64> = match last {
                gson::Value::Absent | gson::Value::Null => None,
                gson::Value::Number(gson::Number::Integer(n)) if n < 0 => {
                    return Err("`last` must be an unsigned integer".to_string())
                }
                gson::Value::Number(gson::Number::Integer(n)) => Some(n as u64),
                _ => {
                    return Err("Internal Error: failed to parse validated last".to_string());
                }
            };

            let offset: gson::Value = read_argument(
                "offset",
                field,
                query_field,
                variables,
                variable_definitions,
            )?;
            let offset: Option<u64> = match offset {
                gson::Value::Absent | gson::Value::Null => None,
                gson::Value::Number(gson::Number::Integer(n)) if n < 0 => {
                    return Err("`offset` must be an unsigned integer".to_string())
                }
                gson::Value::Number(gson::Number::Integer(n)) => Some(n as u64),
                _ => {
                    return Err("Internal Error: failed to parse validated offset".to_string());
                }
            };

            let max_rows = xtype
                .schema
                .context
                .schemas
                .values()
                .find(|s| s.oid == xtype.table.schema_oid)
                .map(|schema| xtype.table.max_rows(schema))
                .unwrap_or(30);

            let before: Option<Cursor> = read_argument_cursor(
                "before",
                field,
                query_field,
                variables,
                variable_definitions,
            )?;
            let after: Option<Cursor> =
                read_argument_cursor("after", field, query_field, variables, variable_definitions)?;

            // Validate compatible input arguments
            if first.is_some() && last.is_some() {
                return Err("only one of \"first\" and \"last\" may be provided".to_string());
            } else if before.is_some() && after.is_some() {
                return Err("only one of \"before\" and \"after\" may be provided".to_string());
            } else if first.is_some() && before.is_some() {
                return Err("\"first\" may only be used with \"after\"".to_string());
            } else if last.is_some() && after.is_some() {
                return Err("\"last\" may only be used with \"before\"".to_string());
            } else if offset.is_some() && (last.is_some() || before.is_some()) {
                // Only support forward pagination with offset
                return Err("\"offset\" may only be used with \"first\" and \"after\"".to_string());
            }

            let filter: FilterBuilder =
                read_argument_filter(field, query_field, variables, variable_definitions)?;
            let order_by: OrderByBuilder =
                read_argument_order_by(field, query_field, variables, variable_definitions)?;

            let mut builder_fields: Vec<ConnectionSelection> = vec![];

            let selection_fields = normalize_selection_set(
                &query_field.selection_set,
                fragment_definitions,
                &type_name,
                variables,
            )?;

            for selection_field in selection_fields {
                match field_map.get(selection_field.name.as_ref()) {
                    None => {
                        let error = if selection_field.name.as_ref() == "aggregate" {
                            "enable the aggregate directive to use aggregates"
                        } else {
                            "unknown field in connection"
                        }
                        .to_string();
                        return Err(error);
                    }
                    Some(f) => builder_fields.push(match &f.type_.unmodified_type() {
                        __Type::Edge(_) => ConnectionSelection::Edge(to_edge_builder(
                            f,
                            &selection_field,
                            fragment_definitions,
                            variables,
                            variable_definitions,
                        )?),
                        __Type::PageInfo(_) => ConnectionSelection::PageInfo(to_page_info_builder(
                            f,
                            &selection_field,
                            fragment_definitions,
                            variables,
                        )?),
                        __Type::Aggregate(_) => {
                            ConnectionSelection::Aggregate(to_aggregate_builder(
                                f,
                                &selection_field,
                                fragment_definitions,
                                variables,
                            )?)
                        }
                        __Type::Scalar(Scalar::Int) => {
                            if selection_field.name.as_ref() == "totalCount" {
                                ConnectionSelection::TotalCount {
                                    alias: alias_or_name(&selection_field),
                                }
                            } else {
                                return Err(format!(
                                    "Unsupported field type for connection field {}",
                                    selection_field.name.as_ref()
                                ));
                            }
                        }
                        __Type::Scalar(Scalar::String(None)) => {
                            if selection_field.name.as_ref() == "__typename" {
                                ConnectionSelection::Typename {
                                    alias: alias_or_name(&selection_field),
                                    typename: xtype
                                        .name()
                                        .expect("connection type should have a name"),
                                }
                            } else {
                                return Err(format!(
                                    "Unsupported field type for connection field {}",
                                    selection_field.name.as_ref()
                                ));
                            }
                        }
                        _ => {
                            return Err(format!(
                                "unknown field type on connection: {}",
                                selection_field.name.as_ref()
                            ))
                        }
                    }),
                }
            }

            Ok(ConnectionBuilder {
                alias,
                source: ConnectionBuilderSource {
                    table: Arc::clone(&xtype.table),
                    fkey: xtype.fkey.clone(),
                },
                first,
                last,
                before,
                offset,
                after,
                filter,
                order_by,
                selections: builder_fields,
                max_rows,
            })
        }
        _ => Err(format!(
            "can not build query for non-connection type {:?}",
            type_.name()
        )),
    }
}

fn to_aggregate_builder<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
) -> Result<AggregateBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();
    let __Type::Aggregate(ref _agg_type) = type_ else {
        return Err("Internal Error: Expected AggregateType in to_aggregate_builder".to_string());
    };

    let alias = alias_or_name(query_field);
    let mut selections = Vec::new();
    let field_map = field_map(&type_); // Get fields of the AggregateType (count, sum, avg, etc.)

    let type_name = type_.name().ok_or("Aggregate type has no name")?;

    let selection_fields = normalize_selection_set(
        &query_field.selection_set,
        fragment_definitions,
        &type_name,
        variables,
    )?;

    for selection_field in selection_fields {
        let field_name = selection_field.name.as_ref();
        let sub_field = field_map.get(field_name).ok_or(format!(
            "Unknown field \"{}\" selected on type \"{}\"",
            field_name, type_name
        ))?;
        let sub_alias = alias_or_name(&selection_field);

        let col_selections = if field_name == "sum"
            || field_name == "avg"
            || field_name == "min"
            || field_name == "max"
        {
            to_aggregate_column_builders(
                sub_field,
                &selection_field,
                fragment_definitions,
                variables,
            )?
        } else {
            vec![]
        };

        selections.push(match field_name {
            "count" => AggregateSelection::Count { alias: sub_alias },
            "sum" => AggregateSelection::Sum {
                alias: sub_alias,
                column_builders: col_selections,
            },
            "avg" => AggregateSelection::Avg {
                alias: sub_alias,
                column_builders: col_selections,
            },
            "min" => AggregateSelection::Min {
                alias: sub_alias,
                column_builders: col_selections,
            },
            "max" => AggregateSelection::Max {
                alias: sub_alias,
                column_builders: col_selections,
            },
            "__typename" => AggregateSelection::Typename {
                alias: sub_alias,
                typename: field
                    .type_()
                    .name()
                    .ok_or("Name for aggregate field's type not found")?
                    .to_string(),
            },
            _ => return Err(format!("Unknown aggregate field: {}", field_name)),
        })
    }

    Ok(AggregateBuilder { alias, selections })
}

fn to_aggregate_column_builders<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
) -> Result<Vec<ColumnBuilder>, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();
    let __Type::AggregateNumeric(_) = type_ else {
        return Err("Internal Error: Expected AggregateNumericType".to_string());
    };
    let mut column_builers = Vec::new();
    let field_map = field_map(&type_);
    let type_name = type_.name().ok_or("AggregateNumeric type has no name")?;
    let selection_fields = normalize_selection_set(
        &query_field.selection_set,
        fragment_definitions,
        &type_name,
        variables,
    )?;

    for selection_field in selection_fields {
        let col_name = selection_field.name.as_ref();
        let sub_field = field_map.get(col_name).ok_or_else(|| {
            format!(
                "Unknown or invalid field \"{}\" selected on type \"{}\"",
                col_name, type_name
            )
        })?;

        let __Type::Scalar(_) = sub_field.type_().unmodified_type() else {
            return Err(format!(
                "Field \"{}\" on type \"{}\" is not a scalar column",
                col_name, type_name
            ));
        };
        let Some(NodeSQLType::Column(column)) = &sub_field.sql_type else {
            return Err(format!(
                "Internal error: Missing column info for aggregate field '{}'",
                col_name
            ));
        };

        let alias = alias_or_name(&selection_field);

        column_builers.push(ColumnBuilder {
            alias,
            column: Arc::clone(column),
        });
    }
    Ok(column_builers)
}

fn to_page_info_builder<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
) -> Result<PageInfoBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();
    let type_name = type_.name().ok_or(format!(
        "Encountered type without name in page info builder: {:?}",
        type_
    ))?;
    let field_map = field_map(&type_);
    let alias = alias_or_name(query_field);

    match type_ {
        __Type::PageInfo(xtype) => {
            let mut builder_fields: Vec<PageInfoSelection> = vec![];

            let selection_fields = normalize_selection_set(
                &query_field.selection_set,
                fragment_definitions,
                &type_name,
                variables,
            )?;

            for selection_field in selection_fields {
                match field_map.get(selection_field.name.as_ref()) {
                    None => return Err("unknown field in pageInfo".to_string()),
                    Some(f) => builder_fields.push(match f.name().as_ref() {
                        "startCursor" => PageInfoSelection::StartCursor {
                            alias: alias_or_name(&selection_field),
                        },
                        "endCursor" => PageInfoSelection::EndCursor {
                            alias: alias_or_name(&selection_field),
                        },
                        "hasPreviousPage" => PageInfoSelection::HasPreviousPage {
                            alias: alias_or_name(&selection_field),
                        },
                        "hasNextPage" => PageInfoSelection::HasNextPage {
                            alias: alias_or_name(&selection_field),
                        },
                        "__typename" => PageInfoSelection::Typename {
                            alias: alias_or_name(&selection_field),
                            typename: xtype.name().expect("page info type should have a name"),
                        },
                        _ => return Err("unexpected field type on pageInfo".to_string()),
                    }),
                }
            }
            Ok(PageInfoBuilder {
                alias,
                selections: builder_fields,
            })
        }
        _ => Err("can not build query for non-PageInfo type".to_string()),
    }
}

fn to_edge_builder<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<EdgeBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();
    let type_name = type_.name().ok_or(format!(
        "Encountered type without name in edge builder: {:?}",
        type_
    ))?;
    let field_map = field_map(&type_);
    let alias = alias_or_name(query_field);

    match type_ {
        __Type::Edge(xtype) => {
            let mut builder_fields = vec![];

            let selection_fields = normalize_selection_set(
                &query_field.selection_set,
                fragment_definitions,
                &type_name,
                variables,
            )?;

            for selection_field in selection_fields {
                match field_map.get(selection_field.name.as_ref()) {
                    None => return Err("unknown field in edge".to_string()),
                    Some(f) => builder_fields.push(match &f.type_.unmodified_type() {
                        __Type::Node(_) => {
                            let node_builder = to_node_builder(
                                f,
                                &selection_field,
                                fragment_definitions,
                                variables,
                                &[],
                                variable_definitions,
                            )?;
                            EdgeSelection::Node(node_builder)
                        }
                        _ => match f.name().as_ref() {
                            "cursor" => EdgeSelection::Cursor {
                                alias: alias_or_name(&selection_field),
                            },
                            "__typename" => EdgeSelection::Typename {
                                alias: alias_or_name(&selection_field),
                                typename: xtype.name().expect("edge type should have a name"),
                            },
                            _ => return Err("unexpected field type on edge".to_string()),
                        },
                    }),
                }
            }
            Ok(EdgeBuilder {
                alias,
                selections: builder_fields,
            })
        }
        _ => Err("can not build query for non-edge type".to_string()),
    }
}

pub fn to_node_builder<'a, T>(
    field: &__Field,
    query_field: &graphql_parser::query::Field<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    variables: &serde_json::Value,
    extra_allowed_args: &[&str],
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<NodeBuilder, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let type_ = field.type_().unmodified_type();

    let alias = alias_or_name(query_field);

    let xtype: NodeType = match type_.return_type() {
        __Type::Node(xtype) => {
            restrict_allowed_arguments(extra_allowed_args, query_field)?;
            xtype.clone()
        }
        __Type::NodeInterface(node_interface) => {
            restrict_allowed_arguments(&["nodeId"], query_field)?;
            // The nodeId argument is only valid on the entrypoint field for Node
            // relationships to "node" e.g. within edges, do not have any arguments
            let node_id: NodeIdInstance =
                read_argument_node_id(field, query_field, variables, variable_definitions)?;

            let possible_types: Vec<__Type> = node_interface.possible_types().unwrap_or(vec![]);
            let xtype = possible_types.iter().find_map(|x| match x {
                __Type::Node(node_type)
                    if node_type.table.schema == node_id.schema_name
                        && node_type.table.name == node_id.table_name =>
                {
                    Some(node_type)
                }
                _ => None,
            });

            match xtype {
                Some(x) => x.clone(),
                None => {
                    return Err(
                        "Collection referenced by nodeId did not match any known collection"
                            .to_string(),
                    );
                }
            }
        }
        _ => {
            return Err("can not build query for non-node type".to_string());
        }
    };

    let type_name = xtype
        .name()
        .ok_or("Encountered type without name in node builder")?;

    let field_map = field_map(&__Type::Node(xtype.clone()));

    let mut builder_fields = vec![];
    let mut allowed_args = vec!["nodeId"];
    allowed_args.extend(extra_allowed_args);
    restrict_allowed_arguments(&allowed_args, query_field)?;

    // The nodeId argument is only valid on the entrypoint field for Node
    // relationships to "node" e.g. within edges, do not have any arguments
    let node_id: Option<NodeIdInstance> = match field.get_arg("nodeId").is_some() {
        true => Some(read_argument_node_id(
            field,
            query_field,
            variables,
            variable_definitions,
        )?),
        false => None,
    };

    let selection_fields = normalize_selection_set(
        &query_field.selection_set,
        fragment_definitions,
        &type_name,
        variables,
    )?;

    for selection_field in selection_fields {
        match field_map.get(selection_field.name.as_ref()) {
            None => {
                return Err(format!(
                    "Unknown field '{}' on type '{}'",
                    selection_field.name.as_ref(),
                    &type_name
                ))
            }
            Some(f) => {
                let alias = alias_or_name(&selection_field);

                let node_selection = match &f.sql_type {
                    Some(node_sql_type) => match node_sql_type {
                        NodeSQLType::Column(col) => NodeSelection::Column(ColumnBuilder {
                            alias,
                            column: Arc::clone(col),
                        }),
                        NodeSQLType::Function(func) => {
                            let function_selection = match &f.type_() {
                                __Type::Scalar(_) => FunctionSelection::ScalarSelf,
                                __Type::List(_) => FunctionSelection::Array,
                                __Type::Node(_) => {
                                    let node_builder = to_node_builder(
                                        f,
                                        &selection_field,
                                        fragment_definitions,
                                        variables,
                                        &[],
                                        variable_definitions,
                                        // TODO need ref to fkey here
                                    )?;
                                    FunctionSelection::Node(node_builder)
                                }
                                __Type::Connection(_) => {
                                    let connection_builder = to_connection_builder(
                                        f,
                                        &selection_field,
                                        fragment_definitions,
                                        variables,
                                        &[], // TODO need ref to fkey here
                                        variable_definitions,
                                    )?;
                                    FunctionSelection::Connection(connection_builder)
                                }
                                _ => return Err("invalid return type from function".to_string()),
                            };
                            NodeSelection::Function(FunctionBuilder {
                                alias,
                                function: Arc::clone(func),
                                table: Arc::clone(&xtype.table),
                                selection: function_selection,
                            })
                        }
                        NodeSQLType::NodeId(pkey_columns) => {
                            NodeSelection::NodeId(NodeIdBuilder {
                                alias,
                                columns: pkey_columns.clone(), // interior is arc
                                table_name: xtype.table.name.clone(),
                                schema_name: xtype.table.schema.clone(),
                            })
                        }
                    },
                    _ => match f.name().as_ref() {
                        "__typename" => NodeSelection::Typename {
                            alias: alias_or_name(&selection_field),
                            typename: xtype.name().expect("node type should have a name"),
                        },
                        _ => match f.type_().unmodified_type() {
                            __Type::Connection(_) => {
                                let con_builder = to_connection_builder(
                                    f,
                                    &selection_field,
                                    fragment_definitions,
                                    variables,
                                    &[],
                                    variable_definitions,
                                );
                                NodeSelection::Connection(con_builder?)
                            }
                            __Type::Node(_) => {
                                let node_builder = to_node_builder(
                                    f,
                                    &selection_field,
                                    fragment_definitions,
                                    variables,
                                    &[],
                                    variable_definitions,
                                );
                                NodeSelection::Node(node_builder?)
                            }
                            _ => {
                                return Err(format!("unexpected field type on node {}", f.name()));
                            }
                        },
                    },
                };
                builder_fields.push(node_selection);
            }
        }
    }
    Ok(NodeBuilder {
        node_id,
        alias,
        table: Arc::clone(&xtype.table),
        fkey: xtype.fkey.clone(),
        reverse_reference: xtype.reverse_reference,
        selections: builder_fields,
    })
}

// Introspection

#[allow(clippy::large_enum_variant)]
#[derive(Serialize, Clone, Debug)]
pub enum __FieldField {
    Name,
    Description,
    Arguments(Vec<__InputValueBuilder>),
    Type(__TypeBuilder),
    IsDeprecated,
    DeprecationReason,
    Typename { alias: String, typename: String },
}

#[derive(Serialize, Clone, Debug)]
pub struct __FieldSelection {
    pub alias: String,
    pub selection: __FieldField,
}
#[derive(Clone, Debug)]
pub struct __FieldBuilder {
    pub field: __Field,
    //pub type_: __Type,
    pub selections: Vec<__FieldSelection>,
}

#[derive(Serialize, Clone, Debug)]
pub enum __EnumValueField {
    Name,
    Description,
    IsDeprecated,
    DeprecationReason,
    Typename { alias: String, typename: String },
}

#[derive(Serialize, Clone, Debug)]
pub struct __EnumValueSelection {
    pub alias: String,
    pub selection: __EnumValueField,
}

#[derive(Clone, Debug)]
pub struct __EnumValueBuilder {
    pub enum_value: __EnumValue,
    pub selections: Vec<__EnumValueSelection>,
}

#[allow(clippy::large_enum_variant)]
#[derive(Serialize, Clone, Debug)]
pub enum __InputValueField {
    Name,
    Description,
    Type(__TypeBuilder),
    DefaultValue,
    IsDeprecated,
    DeprecationReason,
    Typename { alias: String, typename: String },
}

#[derive(Serialize, Clone, Debug)]
pub struct __InputValueSelection {
    pub alias: String,
    pub selection: __InputValueField,
}

#[derive(Clone, Debug)]
pub struct __InputValueBuilder {
    pub input_value: __InputValue,
    pub selections: Vec<__InputValueSelection>,
}

#[allow(clippy::large_enum_variant)]
#[derive(Clone, Debug)]
pub enum __TypeField {
    Kind,
    Name,
    Description,
    // More
    Fields(Option<Vec<__FieldBuilder>>),
    InputFields(Option<Vec<__InputValueBuilder>>),

    Interfaces(Vec<__TypeBuilder>),
    EnumValues(Option<Vec<__EnumValueBuilder>>),
    PossibleTypes(Option<Vec<__TypeBuilder>>),
    OfType(Option<__TypeBuilder>),
    Typename {
        alias: String,
        typename: Option<String>,
    },
}

#[derive(Clone, Debug)]
pub struct __TypeSelection {
    pub alias: String,
    pub selection: __TypeField,
}

#[derive(Clone, Debug)]
pub struct __TypeBuilder {
    pub type_: __Type,
    pub selections: Vec<__TypeSelection>,
}

#[derive(Clone, Debug)]
pub enum __DirectiveField {
    Name,
    Description,
    Locations,
    Args(Vec<__InputValueBuilder>),
    IsRepeatable,
    Typename { alias: String, typename: String },
}

#[derive(Clone, Debug)]
pub struct __DirectiveSelection {
    pub alias: String,
    pub selection: __DirectiveField,
}

#[derive(Clone, Debug)]
pub struct __DirectiveBuilder {
    pub directive: __Directive,
    pub selections: Vec<__DirectiveSelection>,
}

#[derive(Serialize, Clone, Debug)]
#[allow(dead_code)]
#[serde(untagged)]
pub enum __SchemaField {
    Description,
    Types(Vec<__TypeBuilder>),
    QueryType(__TypeBuilder),
    MutationType(Option<__TypeBuilder>),
    SubscriptionType(Option<__TypeBuilder>),
    Directives(Vec<__DirectiveBuilder>),
    Typename { alias: String, typename: String },
}

#[derive(Serialize, Clone, Debug)]
pub struct __SchemaSelection {
    pub alias: String,
    pub selection: __SchemaField,
}

#[derive(Clone)]
pub struct __SchemaBuilder {
    pub description: String,
    pub selections: Vec<__SchemaSelection>,
}

impl __Schema {
    pub fn to_enum_value_builder<'a, T>(
        &self,
        enum_value: &__EnumValue,
        query_field: &graphql_parser::query::Field<'a, T>,
        fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
        variables: &serde_json::Value,
    ) -> Result<__EnumValueBuilder, String>
    where
        T: Text<'a> + Eq + AsRef<str> + Clone,
        T::Value: Hash,
    {
        let selection_fields = normalize_selection_set(
            &query_field.selection_set,
            fragment_definitions,
            &"__EnumValue".to_string(),
            variables,
        )?;

        let mut builder_fields = vec![];

        for selection_field in selection_fields {
            let enum_value_field_name = selection_field.name.as_ref();

            let __enum_value_field = match enum_value_field_name {
                "name" => __EnumValueField::Name,
                "description" => __EnumValueField::Description,
                "isDeprecated" => __EnumValueField::IsDeprecated,
                "deprecationReason" => __EnumValueField::DeprecationReason,
                "__typename" => __EnumValueField::Typename {
                    alias: alias_or_name(&selection_field),
                    typename: enum_value.name(),
                },
                _ => {
                    return Err(format!(
                        "unknown field in __EnumValue: {}",
                        enum_value_field_name
                    ))
                }
            };

            builder_fields.push(__EnumValueSelection {
                alias: alias_or_name(&selection_field),
                selection: __enum_value_field,
            });
        }

        Ok(__EnumValueBuilder {
            enum_value: enum_value.clone(),
            selections: builder_fields,
        })
    }

    pub fn to_input_value_builder<'a, T>(
        &self,
        input_value: &__InputValue,
        query_field: &graphql_parser::query::Field<'a, T>,
        fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
        variables: &serde_json::Value,
        variable_definitions: &Vec<VariableDefinition<'a, T>>,
    ) -> Result<__InputValueBuilder, String>
    where
        T: Text<'a> + Eq + AsRef<str> + Clone,
        T::Value: Hash,
    {
        let selection_fields = normalize_selection_set(
            &query_field.selection_set,
            fragment_definitions,
            &"__InputValue".to_string(),
            variables,
        )?;

        let mut builder_fields = vec![];

        for selection_field in selection_fields {
            let input_value_field_name = selection_field.name.as_ref();

            let __input_value_field = match input_value_field_name {
                "name" => __InputValueField::Name,
                "description" => __InputValueField::Description,
                "type" => {
                    let t = input_value.type_.clone();

                    let t_builder = self.to_type_builder_from_type(
                        &t,
                        &selection_field,
                        fragment_definitions,
                        variables,
                        variable_definitions,
                    )?;
                    __InputValueField::Type(t_builder)
                }
                "defaultValue" => __InputValueField::DefaultValue,
                "isDeprecated" => __InputValueField::IsDeprecated,
                "deprecationReason" => __InputValueField::DeprecationReason,
                "__typename" => __InputValueField::Typename {
                    alias: alias_or_name(&selection_field),
                    typename: input_value.name(),
                },
                _ => {
                    return Err(format!(
                        "unknown field in __InputValue: {}",
                        input_value_field_name
                    ))
                }
            };

            builder_fields.push(__InputValueSelection {
                alias: alias_or_name(&selection_field),
                selection: __input_value_field,
            });
        }

        Ok(__InputValueBuilder {
            input_value: input_value.clone(),
            selections: builder_fields,
        })
    }

    pub fn to_field_builder<'a, T>(
        &self,
        field: &__Field,
        query_field: &graphql_parser::query::Field<'a, T>,
        fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
        variables: &serde_json::Value,
        variable_definitions: &Vec<VariableDefinition<'a, T>>,
    ) -> Result<__FieldBuilder, String>
    where
        T: Text<'a> + Eq + AsRef<str> + Clone,
        T::Value: Hash,
    {
        let selection_fields = normalize_selection_set(
            &query_field.selection_set,
            fragment_definitions,
            &"__Field".to_string(),
            variables,
        )?;

        let mut builder_fields = vec![];

        for selection_field in selection_fields {
            let type_field_name = selection_field.name.as_ref();

            let __field_field = match type_field_name {
                "name" => __FieldField::Name,
                "description" => __FieldField::Description,
                "args" => {
                    let mut f_builders: Vec<__InputValueBuilder> = vec![];
                    let args = field.args();

                    for arg in args {
                        let f_builder = self.to_input_value_builder(
                            &arg,
                            &selection_field,
                            fragment_definitions,
                            variables,
                            variable_definitions,
                        )?;
                        f_builders.push(f_builder)
                    }
                    __FieldField::Arguments(f_builders)
                }
                "type" => {
                    let t = field.type_();

                    let t_builder = self.to_type_builder_from_type(
                        &t,
                        &selection_field,
                        fragment_definitions,
                        variables,
                        variable_definitions,
                    )?;
                    __FieldField::Type(t_builder)
                }
                "isDeprecated" => __FieldField::IsDeprecated,
                "deprecationReason" => __FieldField::DeprecationReason,
                "__typename" => __FieldField::Typename {
                    alias: alias_or_name(&selection_field),
                    typename: field.name(),
                },
                _ => return Err(format!("unknown field in __Field {}", type_field_name)),
            };

            builder_fields.push(__FieldSelection {
                alias: alias_or_name(&selection_field),
                selection: __field_field,
            });
        }

        Ok(__FieldBuilder {
            field: field.clone(),
            selections: builder_fields,
        })
    }

    pub fn to_type_builder<'a, T>(
        &self,
        field: &__Field,
        query_field: &graphql_parser::query::Field<'a, T>,
        fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
        mut type_name: Option<String>,
        variables: &serde_json::Value,
        variable_definitions: &Vec<VariableDefinition<'a, T>>,
    ) -> Result<Option<__TypeBuilder>, String>
    where
        T: Text<'a> + Eq + AsRef<str> + Clone,
        T::Value: Hash,
    {
        if field.type_.unmodified_type() != __Type::__Type(__TypeType {}) {
            return Err("can not build query for non-__type type".to_string());
        }

        let name_arg_result: Result<gson::Value, String> =
            read_argument("name", field, query_field, variables, variable_definitions);
        let name_arg: Option<String> = match name_arg_result {
            // This builder (too) is overloaded and the arg is not present in all uses
            Err(_) => None,
            Ok(name_arg) => match name_arg {
                gson::Value::String(narg) => Some(narg),
                _ => {
                    return Err("Internal Error: failed to parse validated name".to_string());
                }
            },
        };

        if name_arg.is_some() {
            type_name = name_arg;
        }
        let type_name = type_name.ok_or("no name found for __type".to_string())?;

        let type_map = type_map(self);
        let requested_type: Option<&__Type> = type_map.get(&type_name);

        match requested_type {
            Some(requested_type) => {
                // Result<> to Result<Option<>>
                self.to_type_builder_from_type(
                    requested_type,
                    query_field,
                    fragment_definitions,
                    variables,
                    variable_definitions,
                )
                .map(Some)
            }
            None => Ok(None),
        }
    }

    pub fn to_type_builder_from_type<'a, T>(
        &self,
        type_: &__Type,
        query_field: &graphql_parser::query::Field<'a, T>,
        fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
        variables: &serde_json::Value,
        variable_definitions: &Vec<VariableDefinition<'a, T>>,
    ) -> Result<__TypeBuilder, String>
    where
        T: Text<'a> + Eq + AsRef<str> + Clone,
        T::Value: Hash,
    {
        let field_map = field_map(&__Type::__Type(__TypeType {}));

        let selection_fields = normalize_selection_set(
            &query_field.selection_set,
            fragment_definitions,
            &"__Type".to_string(),
            variables,
        )?;

        let mut builder_fields = vec![];

        for selection_field in selection_fields {
            let type_field_name = selection_field.name.as_ref();
            // ex: type_field_field  = 'name'
            match field_map.get(type_field_name) {
                None => return Err(format!("unknown field on __Type: {}", type_field_name)),
                Some(f) => builder_fields.push(__TypeSelection {
                    alias: alias_or_name(&selection_field),
                    selection: match f.name().as_str() {
                        "kind" => __TypeField::Kind,
                        "name" => __TypeField::Name,
                        "description" => __TypeField::Description,
                        "fields" => {
                            // TODO read "include_deprecated" arg.
                            let type_fields = type_.fields(true);
                            match type_fields {
                                None => __TypeField::Fields(None),
                                Some(vec_fields) => {
                                    let mut f_builders: Vec<__FieldBuilder> = vec![];

                                    for vec_field in vec_fields {
                                        if ["__type".to_string(), "__schema".to_string()]
                                            .contains(&vec_field.name())
                                        {
                                            continue;
                                        }

                                        let f_builder = self.to_field_builder(
                                            &vec_field,
                                            &selection_field,
                                            fragment_definitions,
                                            variables,
                                            variable_definitions,
                                        )?;
                                        f_builders.push(f_builder)
                                    }
                                    __TypeField::Fields(Some(f_builders))
                                }
                            }
                        }
                        "inputFields" => {
                            let type_inputs = type_.input_fields();
                            match type_inputs {
                                None => __TypeField::InputFields(None),
                                Some(vec_fields) => {
                                    let mut f_builders: Vec<__InputValueBuilder> = vec![];

                                    for vec_field in vec_fields {
                                        let f_builder = self.to_input_value_builder(
                                            &vec_field,
                                            &selection_field,
                                            fragment_definitions,
                                            variables,
                                            variable_definitions,
                                        )?;
                                        f_builders.push(f_builder)
                                    }
                                    __TypeField::InputFields(Some(f_builders))
                                }
                            }
                        }
                        "interfaces" => {
                            match type_.interfaces() {
                                Some(interfaces) => {
                                    let mut interface_builders = vec![];
                                    for interface in &interfaces {
                                        let interface_builder = self.to_type_builder_from_type(
                                            interface,
                                            &selection_field,
                                            fragment_definitions,
                                            variables,
                                            variable_definitions,
                                        )?;
                                        interface_builders.push(interface_builder);
                                    }
                                    __TypeField::Interfaces(interface_builders)
                                }
                                None => {
                                    // Declares as nullable, but breaks graphiql
                                    __TypeField::Interfaces(vec![])
                                }
                            }
                        }
                        "enumValues" => {
                            let enum_value_builders = match type_.enum_values(true) {
                                Some(enum_values) => {
                                    let mut f_builders: Vec<__EnumValueBuilder> = vec![];
                                    for enum_value in &enum_values {
                                        let f_builder = self.to_enum_value_builder(
                                            enum_value,
                                            &selection_field,
                                            fragment_definitions,
                                            variables,
                                        )?;
                                        f_builders.push(f_builder)
                                    }
                                    Some(f_builders)
                                }
                                None => None,
                            };
                            __TypeField::EnumValues(enum_value_builders)
                        }
                        "possibleTypes" => match type_.possible_types() {
                            Some(types) => {
                                let mut type_builders = vec![];
                                for ty in &types {
                                    let type_builder = self.to_type_builder_from_type(
                                        ty,
                                        &selection_field,
                                        fragment_definitions,
                                        variables,
                                        variable_definitions,
                                    )?;

                                    type_builders.push(type_builder);
                                }
                                __TypeField::PossibleTypes(Some(type_builders))
                            }
                            None => __TypeField::PossibleTypes(None),
                        },
                        "ofType" => {
                            let field_type =
                                if let __Type::FuncCallResponse(func_call_resp_type) = type_ {
                                    func_call_resp_type.return_type.deref()
                                } else {
                                    type_
                                };
                            let unwrapped_type_builder = match field_type {
                                __Type::List(list_type) => {
                                    let inner_type: __Type = (*(list_type.type_)).clone();
                                    Some(self.to_type_builder_from_type(
                                        &inner_type,
                                        &selection_field,
                                        fragment_definitions,
                                        variables,
                                        variable_definitions,
                                    )?)
                                }
                                __Type::NonNull(non_null_type) => {
                                    let inner_type = (*(non_null_type.type_)).clone();
                                    Some(self.to_type_builder_from_type(
                                        &inner_type,
                                        &selection_field,
                                        fragment_definitions,
                                        variables,
                                        variable_definitions,
                                    )?)
                                }
                                _ => None,
                            };
                            __TypeField::OfType(unwrapped_type_builder)
                        }
                        "__typename" => __TypeField::Typename {
                            alias: alias_or_name(&selection_field),
                            typename: type_.name(),
                        },
                        _ => {
                            return Err(format!(
                                "unexpected field {} type on __Type",
                                type_field_name
                            ))
                        }
                    },
                }),
            }
        }

        Ok(__TypeBuilder {
            type_: type_.clone(),
            selections: builder_fields,
        })
    }

    pub fn to_directive_builder<'a, T>(
        &self,
        directive: &__Directive,
        query_field: &graphql_parser::query::Field<'a, T>,
        fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
        variables: &serde_json::Value,
        variable_definitions: &Vec<VariableDefinition<'a, T>>,
    ) -> Result<__DirectiveBuilder, String>
    where
        T: Text<'a> + Eq + AsRef<str> + Clone,
        T::Value: Hash,
    {
        let selection_fields = normalize_selection_set(
            &query_field.selection_set,
            fragment_definitions,
            &__Directive::TYPE.to_string(),
            variables,
        )?;

        let mut builder_fields = vec![];

        for selection_field in selection_fields {
            let field_name = selection_field.name.as_ref();

            let directive_field = match field_name {
                "name" => __DirectiveField::Name,
                "description" => __DirectiveField::Description,
                "locations" => __DirectiveField::Locations,
                "args" => {
                    let mut builders: Vec<__InputValueBuilder> = vec![];
                    let args = directive.args();

                    for arg in args {
                        let builder = self.to_input_value_builder(
                            arg,
                            &selection_field,
                            fragment_definitions,
                            variables,
                            variable_definitions,
                        )?;
                        builders.push(builder)
                    }
                    __DirectiveField::Args(builders)
                }
                "isRepeatable" => __DirectiveField::IsRepeatable,
                "__typename" => __DirectiveField::Typename {
                    alias: alias_or_name(&selection_field),
                    typename: __Directive::TYPE.to_string(),
                },
                _ => {
                    return Err(format!(
                        "unknown field {} in {}",
                        field_name,
                        __Directive::TYPE,
                    ))
                }
            };

            builder_fields.push(__DirectiveSelection {
                alias: alias_or_name(&selection_field),
                selection: directive_field,
            });
        }

        Ok(__DirectiveBuilder {
            directive: directive.clone(),
            selections: builder_fields,
        })
    }

    pub fn to_schema_builder<'a, T>(
        &self,
        field: &__Field,
        query_field: &graphql_parser::query::Field<'a, T>,
        fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
        variables: &serde_json::Value,
        variable_definitions: &Vec<VariableDefinition<'a, T>>,
    ) -> Result<__SchemaBuilder, String>
    where
        T: Text<'a> + Eq + AsRef<str> + Clone,
        T::Value: Hash,
    {
        let type_ = field.type_.unmodified_type();
        let type_name = type_
            .name()
            .ok_or("Encountered type without name in schema builder")?;
        let field_map = field_map(&type_);

        match type_ {
            __Type::__Schema(_) => {
                let mut builder_fields: Vec<__SchemaSelection> = vec![];

                let selection_fields = normalize_selection_set(
                    &query_field.selection_set,
                    fragment_definitions,
                    &type_name,
                    variables,
                )?;

                for selection_field in selection_fields {
                    let field_name = selection_field.name.as_ref();

                    match field_map.get(field_name) {
                        None => return Err(format!("unknown field in __Schema: {}", field_name)),
                        Some(f) => {
                            builder_fields.push(__SchemaSelection {
                                alias: alias_or_name(&selection_field),
                                selection: match f.name().as_str() {
                                    "description" => __SchemaField::Description,
                                    "types" => {
                                        let builders = self
                                            .types()
                                            .iter()
                                            // Filter out intropsection meta-types
                                            //.filter(|x| {
                                            // !x.name().unwrap_or("".to_string()).starts_with("__")
                                            //})
                                            .map(|t| {
                                                self.to_type_builder(
                                                    f,
                                                    &selection_field,
                                                    fragment_definitions,
                                                    t.name(),
                                                    variables,
                                                    variable_definitions,
                                                )
                                                .map(|x| {
                                                    x.expect(
                                                        "type builder should exist for types field",
                                                    )
                                                })
                                            })
                                            // from Vec<Result> to Result<Vec>
                                            .collect::<Result<Vec<_>, _>>()?;
                                        __SchemaField::Types(builders)
                                    }
                                    "queryType" => {
                                        let builder = self.to_type_builder(
                                            f,
                                            &selection_field,
                                            fragment_definitions,
                                            Some("Query".to_string()),
                                            variables,
                                            variable_definitions,
                                        )?;
                                        __SchemaField::QueryType(builder.expect(
                                            "type builder should exist for queryType field",
                                        ))
                                    }
                                    "mutationType" => {
                                        let builder = self.to_type_builder(
                                            f,
                                            &selection_field,
                                            fragment_definitions,
                                            Some("Mutation".to_string()),
                                            variables,
                                            variable_definitions,
                                        )?;
                                        __SchemaField::MutationType(builder)
                                    }
                                    "subscriptionType" => __SchemaField::SubscriptionType(None),
                                    "directives" => {
                                        let builders = self
                                            .directives()
                                            .iter()
                                            .map(|directive| {
                                                self.to_directive_builder(
                                                    directive,
                                                    &selection_field,
                                                    fragment_definitions,
                                                    variables,
                                                    variable_definitions,
                                                )
                                            })
                                            .collect::<Result<Vec<_>, _>>()?;
                                        __SchemaField::Directives(builders)
                                    }
                                    "__typename" => __SchemaField::Typename {
                                        alias: alias_or_name(&selection_field),
                                        typename: field.name(),
                                    },
                                    _ => {
                                        return Err(format!(
                                            "unexpected field {} type on __Schema",
                                            field_name
                                        ))
                                    }
                                },
                            })
                        }
                    }
                }

                Ok(__SchemaBuilder {
                    description: "Represents the GraphQL schema of the database".to_string(),
                    selections: builder_fields,
                })
            }
            _ => Err("can not build query for non-__schema type".to_string()),
        }
    }
}
