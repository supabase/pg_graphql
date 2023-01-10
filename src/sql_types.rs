use cached::proc_macro::cached;
use cached::SizedCache;
use pgx::*;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::sync::Arc;
use std::*;

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ColumnPermissions {
    pub is_insertable: bool,
    pub is_selectable: bool,
    pub is_updatable: bool,
    // admin interface
    // alterable?
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ColumnDirectives {
    pub inflect_names: bool,
    pub name: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Column {
    pub name: String,
    pub type_oid: u32,
    pub type_name: String,
    pub is_not_null: bool,
    pub is_serial: bool,
    pub is_generated: bool,
    pub has_default: bool,
    pub attribute_num: i32,
    pub permissions: ColumnPermissions,
    pub comment: Option<String>,
    pub directives: ColumnDirectives,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct FunctionDirectives {
    pub inflect_names: bool,
    pub name: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct FunctionPermissions {
    pub is_executable: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Function {
    pub oid: u32,
    pub name: String,
    pub schema_name: String,
    pub type_oid: u32,
    pub type_name: String,
    pub comment: Option<String>,
    pub directives: FunctionDirectives,
    pub permissions: FunctionPermissions,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct TablePermissions {
    pub is_insertable: bool,
    pub is_selectable: bool,
    pub is_updatable: bool,
    pub is_deletable: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct EnumPermissions {
    pub is_usable: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct EnumValue {
    pub oid: u32,
    pub name: String,
    pub sort_order: i32,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Enum {
    pub oid: u32,
    pub schema_oid: u32,
    pub name: String,
    pub values: Vec<EnumValue>,
    pub comment: Option<String>,
    pub permissions: EnumPermissions,
    pub directives: EnumDirectives,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct EnumDirectives {
    pub name: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Composite {
    pub oid: u32,
    pub schema_oid: u32,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Index {
    pub table_oid: u32,
    pub column_names: Vec<String>,
    pub is_unique: bool,
    pub is_primary_key: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ForeignKeyTableInfo {
    pub oid: u32,
    // The table's actual name
    pub name: String,
    pub schema: String,
    pub column_names: Vec<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ForeignKeyDirectives {
    pub local_name: Option<String>,
    pub foreign_name: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ForeignKey {
    pub directives: ForeignKeyDirectives,
    pub local_table_meta: ForeignKeyTableInfo,
    pub referenced_table_meta: ForeignKeyTableInfo,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct TableDirectiveTotalCount {
    pub enabled: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct TableDirectiveForeignKey {
    // Equivalent to ForeignKeyDirectives.local_name
    pub local_name: Option<String>,
    pub local_columns: Vec<String>,

    // Equivalent to ForeignKeyDirectives.foreign_name
    pub foreign_name: Option<String>,
    pub foreign_schema: String,
    pub foreign_table: String,
    pub foreign_columns: Vec<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct TableDirectives {
    pub inflect_names: bool,

    // @graphql({"name": "Foo" })
    pub name: Option<String>,

    // @graphql({"totalCount": { "enabled": true } })
    pub total_count: Option<TableDirectiveTotalCount>,

    // @graphql({"primary_key_columns": ["id"]})
    pub primary_key_columns: Option<Vec<String>>,

    /*
    @graphql(
      {
        "foreign_keys": [
          {
            <REQUIRED>
            "local_columns": ["account_id"],
            "foriegn_schema": "public",
            "foriegn_table": "account",
            "foriegn_columns": ["id"],

            <OPTIONAL>
            "local_name": "foo",
            "foreign_name": "bar",
          },
        ]
      }
    )
    */
    pub foreign_keys: Option<Vec<TableDirectiveForeignKey>>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Table {
    pub oid: u32,
    pub name: String,
    pub schema: String,
    pub columns: Vec<Arc<Column>>,
    pub comment: Option<String>,
    pub relkind: String, // r = table, v = view, m = mat view, f = foreign table
    pub permissions: TablePermissions,
    pub indexes: Vec<Index>,
    pub functions: Vec<Arc<Function>>,
    pub directives: TableDirectives,
}

impl Table {
    pub fn primary_key(&self) -> Option<Index> {
        let real_pkey = self.indexes.iter().find(|x| x.is_primary_key);

        if real_pkey.is_some() {
            return real_pkey.cloned();
        }

        // Check for a primary key definition in comment directives
        if let Some(column_names) = &self.directives.primary_key_columns {
            // validate that columns exist on the table
            let mut valid_column_names: Vec<&String> = vec![];
            for column_name in column_names {
                for column in &self.columns {
                    if column_name == &column.name {
                        valid_column_names.push(&column.name);
                    }
                }
            }
            if valid_column_names.len() != column_names.len() {
                // At least one of the column names didn't exist on the table
                // so the primary key directive is not valid
                // Ideally we'd throw an error here instead
                None
            } else {
                Some(Index {
                    table_oid: self.oid,
                    column_names: column_names.clone(),
                    is_unique: true,
                    is_primary_key: true,
                })
            }
        } else {
            None
        }
    }

    pub fn primary_key_columns(&self) -> Vec<&Arc<Column>> {
        self.primary_key()
            .map(|x| x.column_names)
            .unwrap_or(vec![])
            .iter()
            .map(|col_name| {
                self.columns
                    .iter()
                    .find(|col| &col.name == col_name)
                    .expect("Failed to unwrap pkey by column names")
            })
            .collect::<Vec<&Arc<Column>>>()
    }

    pub fn is_any_column_selectable(&self) -> bool {
        self.columns.iter().any(|x| x.permissions.is_selectable)
    }
    pub fn is_any_column_insertable(&self) -> bool {
        self.columns.iter().any(|x| x.permissions.is_insertable)
    }

    pub fn is_any_column_updatable(&self) -> bool {
        self.columns.iter().any(|x| x.permissions.is_updatable)
    }
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct SchemaDirectives {
    pub inflect_names: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Schema {
    pub oid: u32,
    pub name: String,
    pub tables: Vec<Arc<Table>>,
    pub comment: Option<String>,
    pub directives: SchemaDirectives,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Config {
    pub search_path: Vec<String>,
    pub role: String,
    pub schema_version: i32,
}

#[derive(Deserialize, Debug, Eq, PartialEq)]
pub struct Context {
    pub config: Config,
    pub schemas: Vec<Schema>,
    foreign_keys: Vec<Arc<ForeignKey>>,
    pub enums: Vec<Arc<Enum>>,
    pub composites: Vec<Arc<Composite>>,
}

impl Context {
    /// Collect all foreign keys referencing (inbound or outbound) a table
    pub fn foreign_keys(&self) -> Vec<Arc<ForeignKey>> {
        let mut fkeys: Vec<Arc<ForeignKey>> = self.foreign_keys.clone();

        // Add foreign keys defined in comment directives
        for table in self.schemas.iter().flat_map(|x| &x.tables) {
            let directive_fkeys: Vec<TableDirectiveForeignKey> =
                match &table.directives.foreign_keys {
                    Some(keys) => keys.clone(),
                    None => vec![],
                };

            for directive_fkey in directive_fkeys.iter() {
                let referenced_t = match self.get_table_by_name(
                    &directive_fkey.foreign_schema,
                    &directive_fkey.foreign_table,
                ) {
                    Some(t) => t,
                    None => {
                        // No table found with requested name. Skip.
                        continue;
                    }
                };

                let referenced_t_column_names: HashSet<&String> =
                    referenced_t.columns.iter().map(|x| &x.name).collect();

                // Verify all foreign column references are valid
                if !directive_fkey
                    .foreign_columns
                    .iter()
                    .all(|col| referenced_t_column_names.contains(col))
                {
                    // Skip if invalid references exist
                    continue;
                }

                let fk = ForeignKey {
                    local_table_meta: ForeignKeyTableInfo {
                        oid: table.oid,
                        name: table.name.clone(),
                        schema: table.schema.clone(),
                        column_names: directive_fkey.local_columns.clone(),
                    },
                    referenced_table_meta: ForeignKeyTableInfo {
                        oid: referenced_t.oid,
                        name: referenced_t.name.clone(),
                        schema: referenced_t.schema.clone(),
                        column_names: directive_fkey.foreign_columns.clone(),
                    },
                    directives: ForeignKeyDirectives {
                        local_name: directive_fkey.local_name.clone(),
                        foreign_name: directive_fkey.foreign_name.clone(),
                    },
                };

                //panic!("{:?}, {}", fk, self.fkey_is_selectable(&fk));

                fkeys.push(Arc::new(fk));
            }
        }

        fkeys
            .into_iter()
            .filter(|fk| self.fkey_is_selectable(fk))
            .collect()
    }

    /// Check if a type is a composite type
    pub fn is_composite(&self, type_oid: u32) -> bool {
        self.composites.iter().any(|x| x.oid == type_oid)
    }

    pub fn get_table_by_name(
        &self,
        schema_name: &String,
        table_name: &String,
    ) -> Option<&Arc<Table>> {
        self.schemas
            .iter()
            .flat_map(|x| x.tables.iter())
            .find(|x| &x.schema == schema_name && &x.name == table_name)
    }

    pub fn get_table_by_oid(&self, oid: u32) -> Option<&Arc<Table>> {
        self.schemas
            .iter()
            .flat_map(|x| x.tables.iter())
            .find(|x| x.oid == oid)
    }

    /// Check if the local side of a foreign key is comprised of unique columns
    pub fn fkey_is_locally_unique(&self, fkey: &ForeignKey) -> bool {
        let table: &Arc<Table> = match self.get_table_by_oid(fkey.local_table_meta.oid) {
            Some(table) => table,
            None => {
                return false;
            }
        };

        let fkey_columns: HashSet<&String> = fkey.local_table_meta.column_names.iter().collect();

        for index in table.indexes.iter().filter(|x| x.is_unique) {
            let index_column_names: HashSet<&String> = index.column_names.iter().collect();

            if index_column_names
                .iter()
                .all(|col_name| fkey_columns.contains(col_name))
            {
                return true;
            }
        }
        false
    }

    /// Are both sides of the foreign key composed of selectable columns
    pub fn fkey_is_selectable(&self, fkey: &ForeignKey) -> bool {
        let local_table: &Arc<Table> = match self.get_table_by_oid(fkey.local_table_meta.oid) {
            Some(table) => table,
            None => {
                return false;
            }
        };

        let referenced_table: &Arc<Table> =
            match self.get_table_by_oid(fkey.referenced_table_meta.oid) {
                Some(table) => table,
                None => {
                    return false;
                }
            };

        let fkey_local_columns = &fkey.local_table_meta.column_names;
        let fkey_referenced_columns = &fkey.referenced_table_meta.column_names;

        let local_columns_selectable: HashSet<&String> = local_table
            .columns
            .iter()
            .filter(|x| x.permissions.is_selectable)
            .map(|col| &col.name)
            .collect();

        let referenced_columns_selectable: HashSet<&String> = referenced_table
            .columns
            .iter()
            .filter(|x| x.permissions.is_selectable)
            .map(|col| &col.name)
            .collect();

        /*
        if referenced_table.name == "person".to_string() {
            panic!(
                "local {:?}-{:?} remote {:?}-{:?}",
                fkey_local_columns,
                local_columns_selectable,
                fkey_referenced_columns,
                referenced_columns_selectable
            );
        }
        */

        fkey_local_columns
            .iter()
            .all(|col| local_columns_selectable.contains(col))
            && fkey_referenced_columns
                .iter()
                .all(|col| referenced_columns_selectable.contains(col))
    }
}

pub fn load_sql_config() -> Config {
    let query = include_str!("../sql/load_sql_config.sql");
    let sql_result: serde_json::Value = Spi::get_one::<JsonB>(query).unwrap().0;
    let config: Config = serde_json::from_value(sql_result).unwrap();
    config
}

#[cached(
    type = "SizedCache<String, Result<Arc<Context>, String>>",
    create = "{ SizedCache::with_size(250) }",
    convert = r#"{ serde_json::ser::to_string(_config).unwrap() }"#,
    sync_writes = true
)]
pub fn load_sql_context(_config: &Config) -> Result<Arc<Context>, String> {
    // cache value for next query
    let query = include_str!("../sql/load_sql_context.sql");
    let sql_result: serde_json::Value = Spi::get_one::<JsonB>(query).unwrap().0;
    let context: Result<Context, serde_json::Error> = serde_json::from_value(sql_result);
    context.map(Arc::new).map_err(|e| {
        format!(
            "Error while loading schema, check comment directives. {}",
            e.to_string()
        )
    })
}
