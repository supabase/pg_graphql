use crate::sql_types::{Config, Context, Function, TypeCategory, TypeDetails};
use cached::proc_macro::cached;
use cached::SizedCache;
use pgrx::{FromDatum, IntoDatum, JsonB, Spi};
use std::cmp::Ordering;
use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

/// This method is similar to `Spi::get_one` with the only difference
/// being that it calls `client.select` instead of `client.update`.
/// The `client.update` method generates a new transaction id so
/// calling `Spi::get_one` is not possible when postgres is in
/// recovery mode.
pub(crate) fn get_one_readonly<A: FromDatum + IntoDatum>(
    query: &str,
) -> std::result::Result<Option<A>, pgrx::spi::Error> {
    Spi::connect(|client| client.select(query, Some(1), None)?.first().get_one())
}

pub fn load_sql_config() -> Config {
    let query = include_str!("../sql/load_sql_config.sql");
    let sql_result: serde_json::Value = get_one_readonly::<JsonB>(query)
        .expect("failed to read sql config")
        .expect("sql config is missing")
        .0;
    let config: Config =
        serde_json::from_value(sql_result).expect("failed to convert sql config into json");
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
    let sql_result: serde_json::Value = get_one_readonly::<JsonB>(query)
        .expect("failed to read sql context")
        .expect("sql context is missing")
        .0;
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

    /// This pass populates functions for tables
    fn populate_table_functions(mut context: Context) -> Context {
        let mut arg_type_to_func: HashMap<u32, Vec<&Arc<Function>>> = HashMap::new();
        for function in context.functions.iter().filter(|f| f.num_args == 1) {
            let functions = arg_type_to_func.entry(function.arg_types[0]).or_default();
            functions.push(function);
        }
        for table in &mut context.tables.values_mut() {
            if let Some(table) = Arc::get_mut(table) {
                if let Some(functions) = arg_type_to_func.get(&table.reltype) {
                    for function in functions {
                        table.functions.push(Arc::clone(function));
                    }
                }
            }
        }
        context
    }

    context
        .map(type_details)
        .map(column_types)
        .map(populate_table_functions)
        .map(Arc::new)
        .map_err(|e| {
            format!(
                "Error while loading schema, check comment directives. {}",
                e
            )
        })
}
