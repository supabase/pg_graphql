use cached::proc_macro::cached;
use cached::SizedCache;
use pgx::*;
use serde::{Deserialize, Serialize};
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
    pub oid: u32,
    pub table_oid: u32,
    pub name: String,
    pub column_attnums: Vec<i32>,
    pub is_unique: bool,
    pub is_primary_key: bool,
    pub comment: Option<String>,
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
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
pub struct Table {
    pub oid: u32,
    pub name: String,
    pub schema: String,
    pub columns: Vec<Column>,
    pub comment: Option<String>,
    pub permissions: TablePermissions,
    pub indexes: Vec<Index>,
    pub functions: Vec<Function>,
    pub foreign_keys: Vec<ForeignKey>,
    pub directives: TableDirectives,
}

impl Table {
    pub fn primary_key(&self) -> Option<&Index> {
        self.indexes.iter().filter(|x| x.is_primary_key).next()
    }

    pub fn primary_key_columns(&self) -> Vec<&Column> {
        self.primary_key()
            .map(|x| &x.column_attnums)
            .unwrap_or(&vec![])
            .iter()
            .map(|col_num| {
                self.columns
                    .iter()
                    .filter(|col| &col.attribute_num == col_num)
                    .next()
                    .expect("Failed to unwrap pkey by attnum")
            })
            .collect::<Vec<&Column>>()
    }

    pub fn is_any_column_selectable(&self) -> bool {
        self.columns
            .iter()
            .filter(|x| x.permissions.is_selectable)
            .next()
            .is_some()
    }
    pub fn is_any_column_insertable(&self) -> bool {
        self.columns
            .iter()
            .filter(|x| x.permissions.is_insertable)
            .next()
            .is_some()
    }

    pub fn is_any_column_updatable(&self) -> bool {
        self.columns
            .iter()
            .filter(|x| x.permissions.is_updatable)
            .next()
            .is_some()
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
    pub tables: Vec<Table>,
    pub comment: Option<String>,
    pub directives: SchemaDirectives,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq)]
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
    pub enums: Vec<Enum>,
    pub composites: Vec<Composite>,
}

impl Context {
    pub fn is_composite(&self, type_oid: u32) -> bool {
        self.composites
            .iter()
            .filter(|x| x.oid == type_oid)
            .next()
            .is_some()
    }
}

pub fn load_sql_config() -> Config {
    let query = include_str!("../sql/load_sql_config.sql");
    let sql_result: serde_json::Value = Spi::get_one::<JsonB>(query).unwrap().0;
    let config: Config = serde_json::from_value(sql_result).unwrap();
    config
}

#[cached(
    type = "SizedCache<String, Context>",
    create = "{ SizedCache::with_size(250) }",
    convert = r#"{ format!("{}", _config) }"#,
    sync_writes = true
)]
pub fn load_sql_context(_config: &Config) -> Context {
    // cache value for next query
    let query = include_str!("../sql/load_sql_context.sql");
    let sql_result: serde_json::Value = Spi::get_one::<JsonB>(query).unwrap().0;
    //thread::sleep(time::Duration::from_secs(1));
    serde_json::from_value(sql_result).unwrap()
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
        assert!(context.schemas[0].tables.len() == 0);
    }

    #[pg_test]
    fn test_deserialize_sql_config() {
        let config = load_sql_config();
        assert!(config.search_path.contains(&String::from("public")));
    }
}
