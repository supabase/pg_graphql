use pgx::*;
use serde_json;
use std::ffi::{CStr, CString};
use std::ptr;

mod parser;

pg_module_magic!();

#[derive(Debug, Eq, PartialEq)]
pub struct ParseResult {
    pub ast: Option<serde_json::Value>,
    pub errors: Option<String>,
}

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

#[pg_extern]
fn parse_query(query: &str) -> Option<pgx::JsonB> {
    let parse_result = parse(query);
    parse_result.ast.map(|x| pgx::JsonB(x))
}

#[pg_extern]
fn parse_query_errors(query: &str) -> Option<String> {
    let parse_result = parse(query);
    parse_result.errors
}

extension_sql_file!("sql/init.sql", name = "1");
extension_sql_file!("sql/jsonb/jsonb_coalesce.sql", name = "2", requires = ["1"]);
extension_sql_file!(
    "sql/jsonb/jsonb_unnest_recursive_with_jsonpath.sql",
    name = "3",
    requires = ["2"]
);
extension_sql_file!("sql/random/slug.sql", name = "4", requires = ["3"]);
extension_sql_file!("sql/pg/is_array.sql", name = "5", requires = ["4"]);
extension_sql_file!("sql/pg/is_composite.sql", name = "6", requires = ["5"]);
extension_sql_file!("sql/pg/primary_key_types.sql", name = "7", requires = ["6"]);
extension_sql_file!("sql/pg/to_regclass.sql", name = "8", requires = ["7"]);
extension_sql_file!("sql/pg/schema.sql", name = "9", requires = ["8"]);
extension_sql_file!("sql/pg/to_enum_name.sql", name = "10", requires = ["9"]);
extension_sql_file!("sql/pg/first_agg.sql", name = "11", requires = ["10"]);
extension_sql_file!("sql/pg/to_table_name.sql", name = "12", requires = ["11"]);
extension_sql_file!(
    "sql/pg/to_function_name.sql",
    name = "13",
    requires = ["12"]
);
extension_sql_file!(
    "sql/pg/primary_key_columns.sql",
    name = "14",
    requires = ["13"]
);
extension_sql_file!(
    "sql/dialect/to_camel_case.sql",
    name = "15",
    requires = ["14"]
);
extension_sql_file!(
    "sql/ast/ast_pass_strip_loc.sql",
    name = "16",
    requires = ["15"]
);
extension_sql_file!("sql/ast/arg_to_jsonb.sql", name = "17", requires = ["16"]);
extension_sql_file!("sql/ast/value_literal.sql", name = "18", requires = ["17"]);
extension_sql_file!("sql/ast/is_variable.sql", name = "19", requires = ["18"]);
extension_sql_file!("sql/ast/is_literal.sql", name = "20", requires = ["19"]);
extension_sql_file!(
    "sql/ast/ast_pass_fragments.sql",
    name = "21",
    requires = ["20"]
);
extension_sql_file!("sql/ast/name_literal.sql", name = "22", requires = ["21"]);
extension_sql_file!(
    "sql/ast/alias_or_name_literal.sql",
    name = "23",
    requires = ["22"]
);
extension_sql_file!(
    "sql/exception/exception.sql",
    name = "24",
    requires = ["23"]
);
extension_sql_file!(
    "sql/exception/exception_required_argument.sql",
    name = "25",
    requires = ["24"]
);
extension_sql_file!(
    "sql/exception/exception_unknown_field.sql",
    name = "26",
    requires = ["25"]
);
extension_sql_file!("sql/cursor/impl.sql", name = "27", requires = ["26"]);
extension_sql_file!("sql/directive/parse.sql", name = "28", requires = ["27"]);
extension_sql_file!(
    "sql/reflection/type/types/meta_kind.sql",
    name = "29",
    requires = ["27"]
);
extension_sql_file!(
    "sql/reflection/type/types/type_kind.sql",
    name = "30",
    requires = ["29"]
);
extension_sql_file!(
    "sql/reflection/type/types/cardinality.sql",
    name = "31",
    requires = ["30"]
);
extension_sql_file!(
    "sql/reflection/type/tables/_type.sql",
    name = "32",
    requires = ["31"]
);
extension_sql_file!(
    "sql/reflection/type/sql_type_to_graphql_type.sql",
    name = "33",
    requires = ["32"]
);
extension_sql_file!(
    "sql/reflection/type/views/type.sql",
    name = "34",
    requires = ["33"]
);
extension_sql_file!(
    "sql/reflection/type/enum_value.sql",
    name = "35",
    requires = ["34"]
);
extension_sql_file!(
    "sql/reflection/type/rebuild_types.sql",
    name = "36",
    requires = ["35"]
);
extension_sql_file!(
    "sql/reflection/field/field.sql",
    name = "37",
    requires = ["36"]
);
extension_sql_file!(
    "sql/reflection/field/relationship.sql",
    name = "38",
    requires = ["37"]
);
extension_sql_file!(
    "sql/resolve/argument/get_arg_by_name.sql",
    name = "39",
    requires = ["38"]
);
extension_sql_file!(
    "sql/resolve/argument/arg_index.sql",
    name = "40",
    requires = ["39"]
);
extension_sql_file!(
    "sql/resolve/clause/arg_clause.sql",
    name = "41",
    requires = ["40"]
);
extension_sql_file!(
    "sql/resolve/clause/primary_key_clause.sql",
    name = "42",
    requires = ["41"]
);
extension_sql_file!(
    "sql/resolve/clause/join_clause.sql",
    name = "43",
    requires = ["42"]
);
extension_sql_file!(
    "sql/resolve/clause/order_by/to_column_ordering.sql",
    name = "44",
    requires = ["43"]
);
extension_sql_file!(
    "sql/resolve/clause/order_by/order_by_clause.sql",
    name = "45",
    requires = ["44"]
);
extension_sql_file!(
    "sql/resolve/clause/order_by/order_by_enum_to_clause.sql",
    name = "46",
    requires = ["45"]
);
extension_sql_file!(
    "sql/resolve/clause/filter/types/comparison_op.sql",
    name = "47",
    requires = ["46"]
);
extension_sql_file!(
    "sql/resolve/clause/filter/where_clause.sql",
    name = "48",
    requires = ["47"]
);
extension_sql_file!(
    "sql/resolve/clause/filter/text_to_comparison_op.sql",
    name = "49",
    requires = ["48"]
);
extension_sql_file!(
    "sql/resolve/transpile/build_heartbeat.sql",
    name = "50",
    requires = ["49"]
);
extension_sql_file!(
    "sql/resolve/transpile/build_node.sql",
    name = "51",
    requires = ["50"]
);
extension_sql_file!(
    "sql/resolve/transpile/build_connection.sql",
    name = "52",
    requires = ["51"]
);
extension_sql_file!(
    "sql/resolve/transpile/build_delete.sql",
    name = "53",
    requires = ["52"]
);
extension_sql_file!(
    "sql/resolve/transpile/build_insert.sql",
    name = "54",
    requires = ["53"]
);
extension_sql_file!(
    "sql/resolve/transpile/build_update.sql",
    name = "55",
    requires = ["54"]
);
extension_sql_file!(
    "sql/resolve/cache/prepared_statement_exists.sql",
    name = "56",
    requires = ["55"]
);
extension_sql_file!(
    "sql/resolve/cache/prepared_statement_create_clause.sql",
    name = "57",
    requires = ["56"]
);
extension_sql_file!(
    "sql/resolve/cache/cache_key_variable_component.sql",
    name = "58",
    requires = ["57"]
);
extension_sql_file!(
    "sql/resolve/cache/introspection_query_cache.sql",
    name = "59",
    requires = ["58"]
);
extension_sql_file!(
    "sql/resolve/cache/cache_key.sql",
    name = "60",
    requires = ["59"]
);
extension_sql_file!(
    "sql/resolve/cache/prepared_statement_execute_clause.sql",
    name = "61",
    requires = ["60"]
);
extension_sql_file!(
    "sql/resolve/variable_definitions_sort.sql",
    name = "62",
    requires = ["61"]
);
extension_sql_file!(
    "sql/resolve/argument_value_by_name.sql",
    name = "64",
    requires = ["62"]
);
extension_sql_file!(
    "sql/resolve/introspection/resolve_field.sql",
    name = "65",
    requires = ["64"]
);
extension_sql_file!(
    "sql/resolve/introspection/resolve_type.sql",
    name = "66",
    requires = ["65"]
);
extension_sql_file!(
    "sql/resolve/introspection/resolve_enum_values.sql",
    name = "67",
    requires = ["66"]
);
extension_sql_file!(
    "sql/resolve/introspection/resolve_schema.sql",
    name = "68",
    requires = ["67"]
);
extension_sql_file!(
    "sql/reflection/rebuild_schema.sql",
    name = "69",
    requires = ["68"]
);
extension_sql_file!("sql/resolve/resolve.sql", name = "70", requires = ["68"]);

#[cfg(any(test, feature = "pg_test"))]
#[pg_schema]
mod tests {
    use pgx::*;

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
