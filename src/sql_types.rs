use bimap::BiBTreeMap;
use cached::proc_macro::cached;
use cached::SizedCache;
use pgrx::*;
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::hash_map::DefaultHasher;
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
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
    pub type_: Option<Arc<Type>>,
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
    Pseudo,
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
    pub details: Option<TypeDetails>,
}

// `TypeDetails` derives `Deserialized` but is not expected to come
// from the SQL context. Instead, it is populated in a separate pass.
#[derive(Deserialize, Clone, Debug, Eq, PartialEq, Hash)]
pub enum TypeDetails {
    Enum(Arc<Enum>),
    Composite(Arc<Composite>),
    Table(Arc<Table>),
    Element(Arc<Type>),
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
    pub mappings: Option<BiBTreeMap<String, String>>,
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
    pub types: HashMap<u32, Arc<Type>>,
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
        for table in self.tables.values() {
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
}

pub fn load_sql_config() -> Config {
    let query = include_str!("../sql/load_sql_config.sql");
    let sql_result: serde_json::Value = Spi::get_one::<JsonB>(query).unwrap().unwrap().0;
    let config: Config = serde_json::from_value(sql_result).unwrap();
    config
}

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

    /// This pass cross-reference types with its details
    fn type_details(mut context: Context) -> Context {
        let mut array_types = HashMap::new();
        // We process types to cross-reference their details
        for (oid, type_) in context.types.iter_mut() {
            if let Some(mtype) = Arc::get_mut(type_) {
                // It should be possible to get a mutable reference to type at this point
                // as there are no other references to this Arc at this point.

                // Depending on type's category, locate the appropriate piece of information about it
                mtype.details = match mtype.category {
                    TypeCategory::Enum => context.enums.get(oid).cloned().map(TypeDetails::Enum),
                    TypeCategory::Composite => context
                        .composites
                        .iter()
                        .find(|c| c.oid == *oid)
                        .cloned()
                        .map(TypeDetails::Composite),
                    TypeCategory::Table => context.tables.get(oid).cloned().map(TypeDetails::Table),
                    TypeCategory::Array => {
                        // We can't cross-reference with `context.types` here as it is already mutably borrowed,
                        // so we instead memorize the reference to process later
                        if let Some(element_oid) = mtype.array_element_type_oid {
                            array_types.insert(*oid, element_oid);
                        }
                        None
                    }
                    _ => None,
                };
            }
        }

        // Ensure the types are ordered so that we don't run into a situation where we can't
        // update the type anymore as it has been referenced but the type details weren't completed yet
        let referenced_types = array_types.values().copied().collect::<Vec<_>>();
        let mut ordered_types = array_types
            .iter()
            .map(|(k, v)| (*k, *v))
            .collect::<Vec<_>>();
        // We sort them by their presence in referencing. If the type has been referenced,
        // it should be at the top.
        ordered_types.sort_by(|(k1, _), (k2, _)| {
            if referenced_types.contains(k1) && referenced_types.contains(k2) {
                Ordering::Equal
            } else if referenced_types.contains(k1) {
                Ordering::Less
            } else {
                Ordering::Greater
            }
        });

        // Now we're ready to process array types
        for (array_oid, element_oid) in ordered_types {
            // We remove the element type from the map to ensure there is no mutability conflict for when
            // we get a mutable reference to the array type. We will put it back after we're done with it,
            // a few lines below.
            if let Some(element_t) = context.types.remove(&element_oid) {
                if let Some(array_t) = context.types.get_mut(&array_oid) {
                    if let Some(array) = Arc::get_mut(array_t) {
                        // It should be possible to get a mutable reference to type at this point
                        // as there are no other references to this Arc at this point.
                        array.details = Some(TypeDetails::Element(element_t.clone()));
                    } else {
                        // For some reason, we weren't able to get it. It means something have changed
                        // in our logic and we're presenting an assertion violation. Let's report it.
                        // It's a bug.
                        pgrx::warning!(
                            "Assertion violation: array type with OID {} is already referenced",
                            array_oid
                        );
                        continue;
                    }
                    // Put the element type back. NB: Very important to keep this line! It'll be used
                    // further down the loop. There is a check at the end of each loop's iteration that
                    // we actually did this. Being defensive.
                    context.types.insert(element_oid, element_t);
                } else {
                    // We weren't able to find the OID of the array, which is odd because we just got
                    // it from the context. This means we messed something up and it is a bug. Report it.
                    pgrx::warning!(
                        "Assertion violation: array type with OID {} is not found",
                        array_oid
                    );
                    continue;
                }
            } else {
                // We weren't able to find the OID of the element type, which is also odd because we just got
                // it from the context. This means it's a bug as well. Report it.
                pgrx::warning!(
                        "Assertion violation: referenced element type with OID {} of array type with OID {} is not found",
                        element_oid, array_oid);
                continue;
            }

            // Here we are asserting that we did in fact return the element type back to the list. Part of being
            // defensive here.
            if !context.types.contains_key(&element_oid) {
                pgrx::warning!("Assertion violation: referenced element type with OID {} was not returned to the list of types", element_oid );
                continue;
            }
        }

        context
    }

    /// This pass cross-reference column types
    fn column_types(mut context: Context) -> Context {
        // We process tables to cross-reference their columns' types
        for (_oid, table) in context.tables.iter_mut() {
            if let Some(mtable) = Arc::get_mut(table) {
                // It should be possible to get a mutable reference to table at this point
                // as there are no other references to this Arc at this point.

                // We will now iterate over columns
                for column in mtable.columns.iter_mut() {
                    if let Some(mcolumn) = Arc::get_mut(column) {
                        // It should be possible to get a mutable reference to column at this point
                        // as there are no other references to this Arc at this point.

                        // Find a matching type
                        mcolumn.type_ = context.types.get(&mcolumn.type_oid).cloned();
                    }
                }
            }
        }
        context
    }

    context
        .map(type_details)
        .map(column_types)
        .map(Arc::new)
        .map_err(|e| {
            format!(
                "Error while loading schema, check comment directives. {}",
                e
            )
        })
}
