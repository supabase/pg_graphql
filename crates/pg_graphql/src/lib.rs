use crate::graphql::*;
use graphql_engine::omit::Omit;
use graphql_parser::query::parse_query;
use pgrx::{default, extension_sql_file, pg_extern, pg_module_magic, JsonB};
use resolve::resolve_inner;
use serde_json::json;
use transpile::PgrxPgClient;

mod builder;
mod context;
mod graphql;
mod parser_util;
mod pg_client;
mod resolve;
mod sql_types;
mod transpile;

pg_module_magic!();

extension_sql_file!("../sql/schema_version.sql");
extension_sql_file!("../sql/directives.sql");
extension_sql_file!("../sql/raise_exception.sql");
extension_sql_file!("../sql/resolve.sql", requires = [resolve]);

#[allow(non_snake_case, unused_variables)]
#[pg_extern(name = "_internal_resolve")]
fn resolve(
    query: &str,
    variables: default!(Option<JsonB>, "'{}'"),
    operationName: default!(Option<String>, "null"),
    extensions: default!(Option<JsonB>, "null"),
) -> pgrx::JsonB {
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
            let sql_config = context::load_sql_config();
            let context = context::load_sql_context(&sql_config);

            match context {
                Ok(context) => {
                    let graphql_schema = __Schema { context };
                    let variables = variables.map_or(json!({}), |v| v.0);
                    let client = PgrxPgClient;
                    resolve_inner(
                        &client,
                        query_ast,
                        &variables,
                        &operationName,
                        &graphql_schema,
                    )
                }
                Err(err) => GraphQLResponse {
                    data: Omit::Omitted,
                    errors: Omit::Present(vec![ErrorMessage { message: err }]),
                },
            }
        }
    };

    let value: serde_json::Value =
        serde_json::to_value(response).expect("failed to convert response into json");

    pgrx::JsonB(value)
}

#[cfg(any(test, feature = "pg_test"))]
#[pgrx::pg_schema]
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
