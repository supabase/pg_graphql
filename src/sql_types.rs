use cached::proc_macro::cached;
use cached::SizedCache;
use pgx::*;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::*;

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct ColumnPermissions {
    pub is_insertable: bool,
    pub is_selectable: bool,
    pub is_updatable: bool,
    // admin interface
    // alterable?
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct ColumnDirectives {
    pub name: Option<String>,
    pub description: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Column {
    pub name: String,
    pub type_oid: u32,
    pub type_name: String,
    pub max_characters: Option<i32>,
    pub schema_oid: u32,
    pub is_not_null: bool,
    pub is_serial: bool,
    pub is_generated: bool,
    pub has_default: bool,
    pub attribute_num: i32,
    pub permissions: ColumnPermissions,
    pub comment: Option<String>,
    pub directives: ColumnDirectives,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct FunctionDirectives {
    pub name: Option<String>,
    // @graphql({"description": "the address of ..." })
    pub description: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct FunctionPermissions {
    pub is_executable: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Function {
    pub oid: u32,
    pub name: String,
    pub schema_oid: u32,
    pub schema_name: String,
    pub type_oid: u32,
    pub type_name: String,
    pub is_set_of: bool,
    pub comment: Option<String>,
    pub directives: FunctionDirectives,
    pub permissions: FunctionPermissions,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct TablePermissions {
    pub is_insertable: bool,
    pub is_selectable: bool,
    pub is_updatable: bool,
    pub is_deletable: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct TypePermissions {
    pub is_usable: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub enum TypeCategory {
    Enum,
    Composite,
    Table,
    Array,
    Other,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Type {
    pub oid: u32,
    pub schema_oid: u32,
    pub name: String,
    pub category: TypeCategory,
    pub array_element_type_oid: Option<u32>,
    pub table_oid: Option<u32>,
    pub comment: Option<String>,
    pub permissions: TypePermissions,
    pub directives: EnumDirectives,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct EnumValue {
    pub oid: u32,
    pub name: String,
    pub sort_order: i32,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Enum {
    pub oid: u32,
    pub schema_oid: u32,
    pub name: String,
    pub values: Vec<EnumValue>,
    pub array_element_type_oid: Option<u32>,
    pub comment: Option<String>,
    pub permissions: TypePermissions,
    pub directives: EnumDirectives,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct EnumDirectives {
    pub name: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Composite {
    pub oid: u32,
    pub schema_oid: u32,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Index {
    pub table_oid: u32,
    pub column_names: Vec<String>,
    pub is_unique: bool,
    pub is_primary_key: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct ForeignKeyTableInfo {
    pub oid: u32,
    // The table's actual name
    pub name: String,
    pub schema: String,
    pub column_names: Vec<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct ForeignKeyDirectives {
    pub local_name: Option<String>,
    pub foreign_name: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct ForeignKey {
    pub directives: ForeignKeyDirectives,
    pub local_table_meta: ForeignKeyTableInfo,
    pub referenced_table_meta: ForeignKeyTableInfo,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct TableDirectiveTotalCount {
    pub enabled: bool,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
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

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct TableDirectives {
    // @graphql({"name": "Foo" })
    pub name: Option<String>,

    // @graphql({"description": "the address of ..." })
    pub description: Option<String>,

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

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Table {
    pub oid: u32,
    pub name: String,
    pub schema_oid: u32,
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

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct SchemaDirectives {
    // @graphql({"inflect_names": true})
    pub inflect_names: bool,
    // @graphql({"max_rows": 20})
    pub max_rows: u64,
}

#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Schema {
    pub oid: u32,
    pub name: String,
    pub comment: Option<String>,
    pub directives: SchemaDirectives,
}

#[derive(Serialize, Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub struct Config {
    pub search_path: Vec<String>,
    pub role: String,
    pub schema_version: i32,
}

#[derive(Deserialize, Debug, Eq, PartialEq)]
pub struct Context {
    pub config: Config,
    pub schemas: HashMap<u32, Schema>,
    pub tables: HashMap<u32, Arc<Table>>,
    foreign_keys: Vec<Arc<ForeignKey>>,
    types: HashMap<u32, Arc<Type>>,
    pub enums: HashMap<u32, Arc<Enum>>,
    pub composites: Vec<Arc<Composite>>,
}

impl Hash for Context {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Only the config is needed to has ha Context
        self.config.hash(state);
    }
}

impl Context {
    /// Collect all foreign keys referencing (inbound or outbound) a table
    pub fn foreign_keys(&self) -> Vec<Arc<ForeignKey>> {
        let mut fkeys: Vec<Arc<ForeignKey>> = self.foreign_keys.clone();

        // Add foreign keys defined in comment directives
        for (_, table) in &self.tables {
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
        self.tables
            .values()
            .find(|x| &x.schema == schema_name && &x.name == table_name)
    }

    pub fn get_table_by_oid(&self, oid: u32) -> Option<&Arc<Table>> {
        self.tables.get(&oid)
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

        fkey_local_columns
            .iter()
            .all(|col| local_columns_selectable.contains(col))
            && fkey_referenced_columns
                .iter()
                .all(|col| referenced_columns_selectable.contains(col))
    }

    pub fn types(&self) -> HashMap<u32, Arc<Type>> {
        let mut types = self.types.clone();

        for (oid, name, category, array_elem_oid) in vec![
            (16, "bool", TypeCategory::Other, None),
            (17, "bytea", TypeCategory::Other, None),
            (19, "name", TypeCategory::Other, Some(18)),
            (20, "int8", TypeCategory::Other, None),
            (21, "int2", TypeCategory::Other, None),
            (22, "int2vector", TypeCategory::Array, Some(21)),
            (23, "int4", TypeCategory::Other, None),
            (24, "regproc", TypeCategory::Other, None),
            (25, "text", TypeCategory::Other, None),
            (26, "oid", TypeCategory::Other, None),
            (27, "tid", TypeCategory::Other, None),
            (28, "xid", TypeCategory::Other, None),
            (29, "cid", TypeCategory::Other, None),
            (30, "oidvector", TypeCategory::Array, Some(26)),
            (114, "json", TypeCategory::Other, None),
            (142, "xml", TypeCategory::Other, None),
            (143, "_xml", TypeCategory::Array, Some(142)),
            (199, "_json", TypeCategory::Array, Some(114)),
            (210, "_pg_type", TypeCategory::Array, Some(71)),
            (270, "_pg_attribute", TypeCategory::Array, Some(75)),
            (271, "_xid8", TypeCategory::Array, Some(5069)),
            (272, "_pg_proc", TypeCategory::Array, Some(81)),
            (273, "_pg_class", TypeCategory::Array, Some(83)),
            (600, "point", TypeCategory::Other, Some(701)),
            (601, "lseg", TypeCategory::Other, Some(600)),
            (602, "path", TypeCategory::Other, None),
            (603, "box", TypeCategory::Other, Some(600)),
            (604, "polygon", TypeCategory::Other, None),
            (628, "line", TypeCategory::Other, Some(701)),
            (629, "_line", TypeCategory::Array, Some(628)),
            (650, "cidr", TypeCategory::Other, None),
            (651, "_cidr", TypeCategory::Array, Some(650)),
            (700, "float4", TypeCategory::Other, None),
            (701, "float8", TypeCategory::Other, None),
            (718, "circle", TypeCategory::Other, None),
            (719, "_circle", TypeCategory::Array, Some(718)),
            (774, "macaddr8", TypeCategory::Other, None),
            (775, "_macaddr8", TypeCategory::Array, Some(774)),
            (790, "money", TypeCategory::Other, None),
            (791, "_money", TypeCategory::Array, Some(790)),
            (829, "macaddr", TypeCategory::Other, None),
            (869, "inet", TypeCategory::Other, None),
            (1000, "_bool", TypeCategory::Array, Some(16)),
            (1001, "_bytea", TypeCategory::Array, Some(17)),
            (1002, "_char", TypeCategory::Array, Some(18)),
            (1003, "_name", TypeCategory::Array, Some(19)),
            (1005, "_int2", TypeCategory::Array, Some(21)),
            (1006, "_int2vector", TypeCategory::Array, Some(22)),
            (1007, "_int4", TypeCategory::Array, Some(23)),
            (1008, "_regproc", TypeCategory::Array, Some(24)),
            (1009, "_text", TypeCategory::Array, Some(25)),
            (1010, "_tid", TypeCategory::Array, Some(27)),
            (1011, "_xid", TypeCategory::Array, Some(28)),
            (1012, "_cid", TypeCategory::Array, Some(29)),
            (1013, "_oidvector", TypeCategory::Array, Some(30)),
            (1014, "_bpchar", TypeCategory::Array, Some(1042)),
            (1015, "_varchar", TypeCategory::Array, Some(1043)),
            (1016, "_int8", TypeCategory::Array, Some(20)),
            (1017, "_point", TypeCategory::Array, Some(600)),
            (1018, "_lseg", TypeCategory::Array, Some(601)),
            (1019, "_path", TypeCategory::Array, Some(602)),
            (1020, "_box", TypeCategory::Array, Some(603)),
            (1021, "_float4", TypeCategory::Array, Some(700)),
            (1022, "_float8", TypeCategory::Array, Some(701)),
            (1027, "_polygon", TypeCategory::Array, Some(604)),
            (1028, "_oid", TypeCategory::Array, Some(26)),
            (1033, "aclitem", TypeCategory::Other, None),
            (1034, "_aclitem", TypeCategory::Array, Some(1033)),
            (1040, "_macaddr", TypeCategory::Array, Some(829)),
            (1041, "_inet", TypeCategory::Array, Some(869)),
            (1042, "bpchar", TypeCategory::Other, None),
            (1043, "varchar", TypeCategory::Other, None),
            (1082, "date", TypeCategory::Other, None),
            (1083, "time", TypeCategory::Other, None),
            (1114, "timestamp", TypeCategory::Other, None),
            (1115, "_timestamp", TypeCategory::Array, Some(1114)),
            (1182, "_date", TypeCategory::Array, Some(1082)),
            (1183, "_time", TypeCategory::Array, Some(1083)),
            (1184, "timestamptz", TypeCategory::Other, None),
            (1185, "_timestamptz", TypeCategory::Array, Some(1184)),
            (1186, "interval", TypeCategory::Other, None),
            (1187, "_interval", TypeCategory::Array, Some(1186)),
            (1231, "_numeric", TypeCategory::Array, Some(1700)),
            (1263, "_cstring", TypeCategory::Array, Some(2275)),
            (1266, "timetz", TypeCategory::Other, None),
            (1270, "_timetz", TypeCategory::Array, Some(1266)),
            (1560, "bit", TypeCategory::Other, None),
            (1561, "_bit", TypeCategory::Array, Some(1560)),
            (1562, "varbit", TypeCategory::Other, None),
            (1563, "_varbit", TypeCategory::Array, Some(1562)),
            (1700, "numeric", TypeCategory::Other, None),
            (1790, "refcursor", TypeCategory::Other, None),
            (2201, "_refcursor", TypeCategory::Array, Some(1790)),
            (2202, "regprocedure", TypeCategory::Other, None),
            (2203, "regoper", TypeCategory::Other, None),
            (2204, "regoperator", TypeCategory::Other, None),
            (2205, "regclass", TypeCategory::Other, None),
            (2206, "regtype", TypeCategory::Other, None),
            (2207, "_regprocedure", TypeCategory::Array, Some(2202)),
            (2208, "_regoper", TypeCategory::Array, Some(2203)),
            (2209, "_regoperator", TypeCategory::Array, Some(2204)),
            (2210, "_regclass", TypeCategory::Array, Some(2205)),
            (2211, "_regtype", TypeCategory::Array, Some(2206)),
            (2949, "_txid_snapshot", TypeCategory::Array, Some(2970)),
            (2950, "uuid", TypeCategory::Other, None),
            (2951, "_uuid", TypeCategory::Array, Some(2950)),
            (2970, "txid_snapshot", TypeCategory::Other, None),
            (3220, "pg_lsn", TypeCategory::Other, None),
            (3221, "_pg_lsn", TypeCategory::Array, Some(3220)),
            (3614, "tsvector", TypeCategory::Other, None),
            (3615, "tsquery", TypeCategory::Other, None),
            (3642, "gtsvector", TypeCategory::Other, None),
            (3643, "_tsvector", TypeCategory::Array, Some(3614)),
            (3644, "_gtsvector", TypeCategory::Array, Some(3642)),
            (3645, "_tsquery", TypeCategory::Array, Some(3615)),
            (3734, "regconfig", TypeCategory::Other, None),
            (3735, "_regconfig", TypeCategory::Array, Some(3734)),
            (3769, "regdictionary", TypeCategory::Other, None),
            (3770, "_regdictionary", TypeCategory::Array, Some(3769)),
            (3802, "jsonb", TypeCategory::Other, None),
            (3807, "_jsonb", TypeCategory::Array, Some(3802)),
            (3904, "int4range", TypeCategory::Other, None),
            (3905, "_int4range", TypeCategory::Array, Some(3904)),
            (3906, "numrange", TypeCategory::Other, None),
            (3907, "_numrange", TypeCategory::Array, Some(3906)),
            (3908, "tsrange", TypeCategory::Other, None),
            (3909, "_tsrange", TypeCategory::Array, Some(3908)),
            (3910, "tstzrange", TypeCategory::Other, None),
            (3911, "_tstzrange", TypeCategory::Array, Some(3910)),
            (3912, "daterange", TypeCategory::Other, None),
            (3913, "_daterange", TypeCategory::Array, Some(3912)),
            (3926, "int8range", TypeCategory::Other, None),
            (3927, "_int8range", TypeCategory::Array, Some(3926)),
            (4072, "jsonpath", TypeCategory::Other, None),
            (4073, "_jsonpath", TypeCategory::Array, Some(4072)),
            (4089, "regnamespace", TypeCategory::Other, None),
            (4090, "_regnamespace", TypeCategory::Array, Some(4089)),
            (4096, "regrole", TypeCategory::Other, None),
            (4097, "_regrole", TypeCategory::Array, Some(4096)),
            (4191, "regcollation", TypeCategory::Other, None),
            (4192, "_regcollation", TypeCategory::Array, Some(4191)),
            (4451, "int4multirange", TypeCategory::Other, None),
            (4532, "nummultirange", TypeCategory::Other, None),
            (4533, "tsmultirange", TypeCategory::Other, None),
            (4534, "tstzmultirange", TypeCategory::Other, None),
            (4535, "datemultirange", TypeCategory::Other, None),
            (4536, "int8multirange", TypeCategory::Other, None),
            (5038, "pg_snapshot", TypeCategory::Other, None),
            (5039, "_pg_snapshot", TypeCategory::Array, Some(5038)),
            (5069, "xid8", TypeCategory::Other, None),
            (6150, "_int4multirange", TypeCategory::Array, Some(4451)),
            (6151, "_nummultirange", TypeCategory::Array, Some(4532)),
            (6152, "_tsmultirange", TypeCategory::Array, Some(4533)),
            (6153, "_tstzmultirange", TypeCategory::Array, Some(4534)),
            (6155, "_datemultirange", TypeCategory::Array, Some(4535)),
            (6157, "_int8multirange", TypeCategory::Array, Some(4536)),
        ] {
            types.insert(
                oid,
                Arc::new(Type {
                    oid,
                    schema_oid: 11,
                    name: name.to_string(),
                    category,
                    table_oid: None,
                    comment: None,
                    permissions: TypePermissions { is_usable: true },
                    directives: EnumDirectives { name: None },
                    array_element_type_oid: array_elem_oid,
                }),
            );
        }
        types
    }
}

pub fn load_sql_config() -> Config {
    let query = include_str!("../sql/load_sql_config.sql");
    let sql_result: serde_json::Value = Spi::get_one::<JsonB>(query).unwrap().unwrap().0;
    let config: Config = serde_json::from_value(sql_result).unwrap();
    config
}

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

pub fn calculate_hash<T: Hash>(t: &T) -> u64 {
    let mut s = DefaultHasher::new();
    t.hash(&mut s);
    s.finish()
}

#[cached(
    type = "SizedCache<u64, Result<Arc<Context>, String>>",
    create = "{ SizedCache::with_size(250) }",
    convert = r#"{ calculate_hash(_config) }"#,
    sync_writes = true
)]
pub fn load_sql_context(_config: &Config) -> Result<Arc<Context>, String> {
    // cache value for next query
    let query = include_str!("../sql/load_sql_context.sql");
    let sql_result: serde_json::Value = Spi::get_one::<JsonB>(query).unwrap().unwrap().0;
    let context: Result<Context, serde_json::Error> = serde_json::from_value(sql_result);
    context.map(Arc::new).map_err(|e| {
        format!(
            "Error while loading schema, check comment directives. {}",
            e.to_string()
        )
    })
}
