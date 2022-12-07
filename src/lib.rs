use crate::graphql::*;
use crate::omit::Omit;
use graphql_parser::query::parse_query;
use pgx::*;
use resolve::resolve_inner;
use serde_json::json;
use std::rc::Rc;

mod builder;
mod graphql;
mod omit;
mod parser_util;
mod resolve;
mod sql_types;
mod transpile;

pg_module_magic!();

extension_sql_file!("../sql/schema_version.sql");
extension_sql_file!("../sql/directives.sql");
extension_sql_file!("../sql/raise_exception.sql");

#[allow(non_snake_case, unused_variables)]
#[pg_extern]
fn resolve(
    query: &str,
    variables: default!(Option<JsonB>, "'{}'"),
    operationName: default!(Option<String>, "null"),
    extensions: default!(Option<JsonB>, "null"),
) -> pgx::JsonB {
    // Parse the GraphQL Query
    let query_ast_option = parse_query::<&str>(query);

    let response: GraphQLResponse = match query_ast_option {
        // Parser errors
        Err(err) => {
            let errors = vec![ErrorMessage {
                message: err.to_string(),
            }];

            GraphQLResponse {
                data: Omit::Omitted,
                errors: Omit::Present(errors),
            }
        }
        Ok(query_ast) => {
            let sql_config = sql_types::load_sql_config();

            // TODO: COMMENT HERE ABOUNT CACHING, THREAD, ETC
            let cache = unsafe {
                let _ = CACHE.get_or_init(|| Cache::new(250, 250));
                CACHE.get_mut()
            }
            .unwrap();

            let context = if let Some(rc_sql_context) = cache.get(&sql_config) {
                rc_sql_context.clone()
            } else {
                let sql_context = sql_types::load_sql_context(&sql_config);
                let rc_sql_context = Rc::new(sql_context);
                cache.insert(sql_config, rc_sql_context.clone());
                rc_sql_context
            };

            let graphql_schema = __Schema { context };
            let variables = variables.map_or(json!({}), |v| v.0);
            resolve_inner(query_ast, &variables, &operationName, &graphql_schema)
        }
    };

    let value: serde_json::Value = serde_json::to_value(&response).unwrap();

    pgx::JsonB(value)
}

use once_cell::unsync::OnceCell;
use quick_cache::unsync::Cache;

static mut CACHE: OnceCell<Cache<sql_types::Config, Rc<sql_types::Context>>> = OnceCell::new();

#[cfg(any(test, feature = "pg_test"))]
#[pg_schema]
mod tests {}

#[cfg(test)]
pub mod pg_test {
    pub fn setup(_options: Vec<&str>) {
        // perform one-off initialization when the pg_test framework starts
    }

    pub fn postgresql_conf_options() -> Vec<&'static str> {
        // return any postgresql.conf settings that are required for your tests
        vec![]
    }
}
