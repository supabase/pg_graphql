use cached::proc_macro::cached;
use cached::SizedCache;
use pgx::*;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::*;

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ColumnPermissions {
    pub is_insertable: bool,
    pub is_selectable: bool,
    pub is_updatable: bool,
    // admin interface
    // alterable?
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ColumnDirectives {
    pub inflect_names: bool,
    pub name: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
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

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct FunctionDirectives {
    pub inflect_names: bool,
    pub name: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct FunctionPermissions {
    pub is_executable: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
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

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct TablePermissions {
    pub is_insertable: bool,
    pub is_selectable: bool,
    pub is_updatable: bool,
    pub is_deletable: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct EnumPermissions {
    pub is_usable: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct EnumValue {
    pub oid: u32,
    pub name: String,
    pub sort_order: i32,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Enum {
    pub oid: u32,
    pub schema_oid: u32,
    pub name: String,
    pub values: Vec<EnumValue>,
    pub comment: Option<String>,
    pub permissions: EnumPermissions,
    pub directives: EnumDirectives,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct EnumDirectives {
    pub name: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Composite {
    pub oid: u32,
    pub schema_oid: u32,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Index {
    //pub oid: u32,
    pub table_oid: u32,
    //pub name: String,
    pub column_attnums: Vec<i32>,
    pub is_unique: bool,
    pub is_primary_key: bool,
    //pub comment: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ForeignKeyPermissions {
    // Are tables + columns on both sides of the fkey selectable?
    pub is_selectable: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ForeignKeyTableInfo {
    pub oid: u32,
    // The table's actual name
    pub name: String,
    pub column_attnums: Vec<i32>,
    pub column_names: Vec<String>,
    pub directives: TableDirectives,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ForeignKeyDirectives {
    pub inflect_names: bool,
    pub local_name: Option<String>,
    pub foreign_name: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct ForeignKey {
    pub oid: u32,
    pub name: String,
    pub is_locally_unique: bool,
    pub permissions: ForeignKeyPermissions,
    pub directives: ForeignKeyDirectives,
    pub local_table_meta: ForeignKeyTableInfo,
    pub referenced_table_meta: ForeignKeyTableInfo,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct TableDirectiveTotalCount {
    pub enabled: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct TableDirectives {
    pub inflect_names: bool,
    pub name: Option<String>,
    // XXX: comment directive key is totalCount
    pub total_count: Option<TableDirectiveTotalCount>,

    // Views / Materialized Views only:
    // @graphql({"primary_key_columns": ["id"]})
    pub primary_key_columns: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
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
    pub foreign_keys: Vec<Arc<ForeignKey>>,
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
            let mut column_attnums: Vec<i32> = vec![];
            for column_name in column_names {
                for column in &self.columns {
                    if column_name == &column.name {
                        column_attnums.push(column.attribute_num);
                    }
                }
            }
            if column_attnums.len() != column_names.len() {
                // At least one of the column names didn't exist on the table
                // so the primary key directive is not valid
                // Ideally we'd throw an error here instead
                None
            } else {
                Some(Index {
                    table_oid: self.oid,
                    column_attnums,
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
            .map(|x| x.column_attnums)
            .unwrap_or(vec![])
            .iter()
            .map(|col_num| {
                self.columns
                    .iter()
                    .find(|col| &col.attribute_num == col_num)
                    .expect("Failed to unwrap pkey by attnum")
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

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct SchemaDirectives {
    pub inflect_names: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Schema {
    pub oid: u32,
    pub name: String,
    pub tables: Vec<Arc<Table>>,
    pub comment: Option<String>,
    pub directives: SchemaDirectives,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Config {
    pub search_path: Vec<String>,
    pub role: String,
    pub schema_version: i32,
}

impl fmt::Display for Config {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        // Customize so only `x` and `y` are denoted.
        write!(
            f,
            "{}-{:?}-{}",
            self.schema_version, self.search_path, self.role
        )
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Context {
    pub config: Config,
    pub schemas: Vec<Schema>,
    pub enums: Vec<Arc<Enum>>,
    pub composites: Vec<Arc<Composite>>,
}

impl Context {
    pub fn is_composite(&self, type_oid: u32) -> bool {
        self.composites.iter().any(|x| x.oid == type_oid)
    }
}

pub fn load_sql_config() -> Config {
    let query = include_str!("../sql/load_sql_config.sql");
    let sql_result: serde_json::Value = Spi::get_one::<JsonB>(query).unwrap().0;
    let config: Config = serde_json::from_value(sql_result).unwrap();
    config
}

#[cached(
    type = "SizedCache<String, Arc<Context>>",
    create = "{ SizedCache::with_size(250) }",
    convert = r#"{ format!("{}", _config) }"#,
    sync_writes = true
)]
pub fn load_sql_context(_config: &Config) -> Arc<Context> {
    // cache value for next query
    let query = include_str!("../sql/load_sql_context.sql");
    let sql_result: serde_json::Value = Spi::get_one::<JsonB>(query).unwrap().0;
    let context: Context = serde_json::from_value(sql_result).unwrap();
    Arc::new(context)
}

#[cfg(any(test, feature = "pg_test"))]
#[pgx::pg_schema]
mod tests {
    use crate::sql_types::{load_sql_config, load_sql_context};
    use pgx::*;

    #[pg_test]
    fn test_deserialize_sql_context() {
        let config = load_sql_config();
        let context = load_sql_context(&config);
        assert!(context.schemas.len() == 1);
        assert!(context.schemas[0].tables.is_empty());
    }

    #[pg_test]
    fn test_deserialize_sql_config() {
        let config = load_sql_config();
        assert!(config.search_path.contains(&String::from("public")));
    }
}
