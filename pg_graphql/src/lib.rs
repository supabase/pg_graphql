use pgx::*;
use serde::{Deserialize, Serialize};
use serde_json;
use std::ffi::{CStr, CString};
use std::ptr;

mod parser;

pg_module_magic!();

#[pg_extern]
fn hello_pg_graphql() -> &'static str {
    "Hello, pg_graphql"
}

#[derive(PostgresType, Serialize, Deserialize, Debug, Eq, PartialEq)]
pub struct ParseResult {
    pub ast: Option<serde_json::Value>,
    pub errors: Option<String>,
}

#[pg_extern]
fn parse(query: &str) -> ParseResult {
    let q = CString::new(query).unwrap();
    let q_ptr = q.as_ptr();

    let e_ptr: *mut *const i8 = &mut ptr::null();

    unsafe {
        let ast_ptr: *mut parser::GraphQLAstNode = parser::graphql_parse_string(q_ptr, e_ptr);
        let maybe_ast: Option<&parser::GraphQLAstNode> = ast_ptr.as_ref();

        let parse_result: ParseResult = match maybe_ast {
            None => {
                let errors_c_str = CStr::from_ptr(*e_ptr);

                ParseResult {
                    ast: None,
                    errors: Some(
                        errors_c_str
                            .to_str()
                            .expect("failed to parse query errors")
                            .to_string(),
                    ),
                }
            }
            Some(ref_ast) => {
                let json: *const ::std::os::raw::c_char =
                    parser::graphql_ast_to_json(ref_ast as *const parser::GraphQLAstNode);
                let c_str = CStr::from_ptr(json);

                let ast_str = c_str.to_str().expect("failed to parse query ast");

                ParseResult {
                    ast: Some(
                        serde_json::from_str(ast_str).expect("failed to parse query ast json"),
                    ),
                    errors: None,
                }
            }
        };
        parser::graphql_error_free(*e_ptr);
        parser::graphql_node_free(ast_ptr);

        parse_result
    }
}

#[cfg(any(test, feature = "pg_test"))]
#[pg_schema]
mod tests {
    use pgx::*;

    #[pg_test]
    fn test_hello_pg_graphql() {
        assert_eq!("Hello, pg_graphql", crate::hello_pg_graphql());
    }

    #[pg_test]
    fn test_parse_success() {
        let parsed = crate::parse("{ heartbeat }");
        assert_eq!(parsed.ast.unwrap()["kind"], "Document");
        assert_eq!(parsed.errors, None);
    }

    #[pg_test]
    fn test_parse_error() {
        assert_eq!(
            crate::parse("{ { }"),
            crate::ParseResult {
                ast: None,
                errors: Some("1.3: syntax error, unexpected {".to_string()),
            }
        );
    }
}

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
