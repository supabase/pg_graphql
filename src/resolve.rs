use std::collections::HashSet;
use std::hash::Hash;

use crate::builder::*;
use crate::constants::introspection;
use crate::error::{GraphQLError, GraphQLResult};
use crate::graphql::*;
use crate::omit::*;
use crate::parser_util::*;
use crate::sql_types::get_one_readonly;
use crate::transpile::{MutationEntrypoint, QueryEntrypoint};
use graphql_parser::query::Selection;
use graphql_parser::query::{
    Definition, Document, FragmentDefinition, Mutation, OperationDefinition, Query, SelectionSet,
    Text, VariableDefinition,
};
use itertools::Itertools;
use serde_json::{Value, json};

#[allow(non_snake_case)]
pub fn resolve_inner<'a, T>(
    document: Document<'a, T>,
    variables: &Value,
    operation_name: &Option<String>,
    schema: &__Schema,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    match variables {
        serde_json::Value::Object(_) => (),
        _ => {
            return GraphQLResponse {
                data: Omit::Omitted,
                errors: Omit::Present(vec![ErrorMessage {
                    message: "variables must be an object".to_string(),
                }]),
            };
        }
    }

    // Removes FragmentDefinitions
    let mut operation_defs: Vec<OperationDefinition<T>> = vec![];
    let mut fragment_defs: Vec<FragmentDefinition<T>> = vec![];

    for def in document.definitions {
        match def {
            Definition::Operation(v) => operation_defs.push(v),
            Definition::Fragment(v) => fragment_defs.push(v),
        }
    }

    let operation_names: Vec<Option<String>> = operation_defs
        .iter()
        .map(|def| match def {
            OperationDefinition::Query(q) => q.name.as_ref().map(|x| x.as_ref().to_string()),
            OperationDefinition::Mutation(m) => m.name.as_ref().map(|x| x.as_ref().to_string()),
            _ => None,
        })
        .collect();

    if operation_names.iter().filter(|x| x.is_none()).count() >= 1 && operation_names.len() > 1 {
        return GraphQLResponse {
            data: Omit::Omitted,
            errors: Omit::Present(vec![ErrorMessage {
                message: "Anonymous operations must be the only defined operation".to_string(),
            }]),
        };
    }

    if operation_names.iter().unique().count() != operation_names.len() {
        return GraphQLResponse {
            data: Omit::Omitted,
            errors: Omit::Present(vec![ErrorMessage {
                message: "Operation names must be unique".to_string(),
            }]),
        };
    }

    let maybe_op: Option<OperationDefinition<T>> = operation_defs
        .into_iter()
        .zip(&operation_names)
        .find(|x|
            // Names matche
            x.1 == operation_name
            // Or only 1 operation, and requested operation_name is None
            || (operation_names.len() == 1 && operation_name.is_none() ))
        .map(|x| x.0);

    for fd in &fragment_defs {
        match detect_fragment_cycles(fd, &mut HashSet::new(), &fragment_defs, 1) {
            Ok(()) => {}
            Err(message) => {
                return GraphQLResponse {
                    data: Omit::Omitted,
                    errors: Omit::Present(vec![ErrorMessage {
                        message: message.to_string(),
                    }]),
                };
            }
        }
    }

    match maybe_op {
        None => GraphQLResponse {
            data: Omit::Omitted,
            errors: Omit::Present(vec![ErrorMessage {
                message: "Operation not found".to_string(),
            }]),
        },
        Some(op) => {
            // Limit the depth complexity of a query to prevent DoS attacks
            let depth_check = match &op {
                OperationDefinition::Query(query) => {
                    validate_selection_depth(&query.selection_set, &fragment_defs, 1)
                }
                OperationDefinition::SelectionSet(selection_set) => {
                    validate_selection_depth(selection_set, &fragment_defs, 1)
                }
                OperationDefinition::Mutation(mutation) => {
                    validate_selection_depth(&mutation.selection_set, &fragment_defs, 1)
                }
                OperationDefinition::Subscription(_) => Ok(()),
            };

            if let Err(err) = depth_check {
                return GraphQLResponse {
                    data: Omit::Omitted,
                    errors: Omit::Present(vec![ErrorMessage {
                        message: err.to_string(),
                    }]),
                };
            }

            match op {
                OperationDefinition::Query(query) => {
                    resolve_query(query, schema, variables, fragment_defs)
                }
                OperationDefinition::SelectionSet(selection_set) => {
                    resolve_selection_set(selection_set, schema, variables, fragment_defs, &vec![])
                }
                OperationDefinition::Mutation(mutation) => {
                    resolve_mutation(mutation, schema, variables, fragment_defs)
                }
                OperationDefinition::Subscription(_) => GraphQLResponse {
                    data: Omit::Omitted,
                    errors: Omit::Present(vec![ErrorMessage {
                        message: "Subscriptions are not supported".to_string(),
                    }]),
                },
            }
        }
    }
}

/// Maximum depth of nested field selections allowed in a single operation.
const MAX_SELECTION_DEPTH: u32 = 32;

/// Validate that the depth of the query doesn't exceed [`MAX_SELECTION_DEPTH`].
/// Each nested field adds one to the depth score. Nested fields in fragment
/// spreads or inline fragments are also counted.
fn validate_selection_depth<'a, 'b, T>(
    selection_set: &'b SelectionSet<'a, T>,
    fragment_definitions: &'b [FragmentDefinition<'a, T>],
    depth: u32,
) -> GraphQLResult<()>
where
    T: Text<'a>,
{
    if depth > MAX_SELECTION_DEPTH {
        return Err(GraphQLError::validation(format!(
            "Query selection depth exceeds the maximum allowed depth of {MAX_SELECTION_DEPTH}"
        )));
    }
    for selection in &selection_set.items {
        match selection {
            Selection::Field(field) => {
                validate_selection_depth(&field.selection_set, fragment_definitions, depth + 1)?;
            }
            Selection::FragmentSpread(fragment_spread) => {
                for fd in fragment_definitions {
                    if fd.name == fragment_spread.fragment_name {
                        validate_selection_depth(&fd.selection_set, fragment_definitions, depth)?;
                        break;
                    }
                }
            }
            Selection::InlineFragment(inline_fragment) => {
                validate_selection_depth(
                    &inline_fragment.selection_set,
                    fragment_definitions,
                    depth,
                )?;
            }
        }
    }
    Ok(())
}

fn resolve_query<'a, 'b, T>(
    query: Query<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let variable_definitions = &query.variable_definitions;
    resolve_selection_set(
        query.selection_set,
        schema_type,
        variables,
        fragment_definitions,
        variable_definitions,
    )
}

fn resolve_selection_set<'a, 'b, T>(
    selection_set: SelectionSet<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    use crate::graphql::*;

    let query_type = schema_type.query_type();
    let map = field_map(&query_type);

    let query_type_name = query_type.name().expect("query type should have a name");
    let selections = match normalize_selection_set(
        &selection_set,
        &fragment_definitions,
        &query_type_name,
        variables,
    ) {
        Ok(selections) => selections,
        Err(err) => {
            return GraphQLResponse {
                data: Omit::Omitted,
                errors: Omit::Present(vec![ErrorMessage {
                    message: err.to_string(),
                }]),
            };
        }
    };

    match selections[..] {
        [] => GraphQLResponse {
            data: Omit::Omitted,
            errors: Omit::Present(vec![ErrorMessage {
                message: "Selection set must not be empty".to_string(),
            }]),
        },
        _ => {
            let mut res_data: serde_json::Value = json!({});
            let mut res_errors: Vec<ErrorMessage> = vec![];

            // selection = graphql_parser::query::Field
            for selection in selections.iter() {
                // accountCollection. Top level selections on the query type
                let maybe_field_def = map.get(selection.name.as_ref());

                match maybe_field_def {
                    None => {
                        res_errors.push(ErrorMessage {
                            message: format!(
                                "Unknown field {:?} on type {}",
                                selection.name, query_type_name
                            ),
                        });
                    }
                    Some(field_def) => match field_def.type_.unmodified_type() {
                        __Type::Connection(_) => {
                            let connection_builder = to_connection_builder(
                                field_def,
                                selection,
                                &fragment_definitions,
                                variables,
                                &[],
                                variable_definitions,
                            );

                            match connection_builder {
                                Ok(builder) => match builder.execute() {
                                    Ok(d) => {
                                        res_data[alias_or_name(selection)] = d;
                                    }
                                    Err(msg) => res_errors.push(ErrorMessage {
                                        message: msg.to_string(),
                                    }),
                                },
                                Err(msg) => res_errors.push(ErrorMessage {
                                    message: msg.to_string(),
                                }),
                            }
                        }
                        __Type::NodeInterface(_) => {
                            let node_builder = to_node_builder(
                                field_def,
                                selection,
                                &fragment_definitions,
                                variables,
                                &[],
                                variable_definitions,
                            );

                            match node_builder {
                                Ok(builder) => match builder.execute() {
                                    Ok(d) => {
                                        res_data[alias_or_name(selection)] = d;
                                    }
                                    Err(msg) => res_errors.push(ErrorMessage {
                                        message: msg.to_string(),
                                    }),
                                },
                                Err(msg) => res_errors.push(ErrorMessage {
                                    message: msg.to_string(),
                                }),
                            }
                        }
                        __Type::Node(_) => {
                            // Node types at Query level are *ByPk fields with primary key column args
                            let node_by_pk_builder = to_node_by_pk_builder(
                                field_def,
                                selection,
                                &fragment_definitions,
                                variables,
                                variable_definitions,
                            );

                            match node_by_pk_builder {
                                Ok(builder) => match builder.execute() {
                                    Ok(d) => {
                                        res_data[alias_or_name(selection)] = d;
                                    }
                                    Err(msg) => res_errors.push(ErrorMessage {
                                        message: msg.to_string(),
                                    }),
                                },
                                Err(msg) => res_errors.push(ErrorMessage {
                                    message: msg.to_string(),
                                }),
                            }
                        }
                        __Type::__Type(_) => {
                            let __type_builder = schema_type.to_type_builder(
                                field_def,
                                selection,
                                &fragment_definitions,
                                None,
                                variables,
                                variable_definitions,
                            );

                            match __type_builder {
                                Ok(builder) => {
                                    res_data[alias_or_name(selection)] = serde_json::json!(builder);
                                }
                                Err(msg) => res_errors.push(ErrorMessage {
                                    message: msg.to_string(),
                                }),
                            }
                        }
                        __Type::__Schema(_) => {
                            let __schema_builder = schema_type.to_schema_builder(
                                field_def,
                                selection,
                                &fragment_definitions,
                                variables,
                                variable_definitions,
                            );

                            match __schema_builder {
                                Ok(builder) => {
                                    res_data[alias_or_name(selection)] = serde_json::json!(builder);
                                }
                                Err(msg) => res_errors.push(ErrorMessage {
                                    message: msg.to_string(),
                                }),
                            }
                        }
                        _ => match field_def.name().as_ref() {
                            introspection::TYPENAME => {
                                res_data[alias_or_name(selection)] =
                                    serde_json::json!(query_type.name())
                            }
                            "heartbeat" => {
                                let now_jsonb: pgrx::JsonB =
                                    get_one_readonly("select to_jsonb(now())")
                                        .expect("Internal error: queries should not fail")
                                        .expect("Internal Error: queries should not return null");
                                let now_json = now_jsonb.0;
                                res_data[alias_or_name(selection)] = now_json;
                            }
                            _ => {
                                let function_call_builder = to_function_call_builder(
                                    field_def,
                                    selection,
                                    &fragment_definitions,
                                    variables,
                                    variable_definitions,
                                );

                                match function_call_builder {
                                    Ok(builder) => {
                                        match <FunctionCallBuilder as QueryEntrypoint>::execute(
                                            &builder,
                                        ) {
                                            Ok(d) => {
                                                res_data[alias_or_name(selection)] = d;
                                            }
                                            Err(msg) => res_errors.push(ErrorMessage {
                                                message: msg.to_string(),
                                            }),
                                        }
                                    }
                                    Err(msg) => res_errors.push(ErrorMessage {
                                        message: msg.to_string(),
                                    }),
                                }
                            }
                        },
                    },
                }
            }
            let any_field_succeeded = res_data.as_object().map(|o| !o.is_empty()).unwrap_or(false);
            GraphQLResponse {
                data: if res_errors.is_empty() || any_field_succeeded {
                    Omit::Present(res_data)
                } else {
                    Omit::Present(serde_json::Value::Null)
                },
                errors: match res_errors.len() {
                    0 => Omit::Omitted,
                    _ => Omit::Present(res_errors),
                },
            }
        }
    }
}

fn resolve_mutation<'a, 'b, T>(
    query: Mutation<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let variable_definitions = &query.variable_definitions;
    resolve_mutation_selection_set(
        query.selection_set,
        schema_type,
        variables,
        fragment_definitions,
        variable_definitions,
    )
}

fn resolve_mutation_selection_set<'a, 'b, T>(
    selection_set: SelectionSet<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    use crate::graphql::*;

    let mutation_type = match schema_type.mutation_type() {
        Some(mut_type) => mut_type,
        None => {
            return GraphQLResponse {
                data: Omit::Present(serde_json::Value::Null),
                errors: Omit::Present(vec![ErrorMessage {
                    message: "Unknown type Mutation".to_string(),
                }]),
            };
        }
    };

    let map = field_map(&mutation_type);

    let mutation_type_name = mutation_type
        .name()
        .expect("mutation type should have a name");
    let selections = match normalize_selection_set(
        &selection_set,
        &fragment_definitions,
        &mutation_type_name,
        variables,
    ) {
        Ok(selections) => selections,
        Err(err) => {
            return GraphQLResponse {
                data: Omit::Omitted,
                errors: Omit::Present(vec![ErrorMessage {
                    message: err.to_string(),
                }]),
            };
        }
    };

    use pgrx::prelude::*;

    let spi_result: GraphQLResult<serde_json::Value> = Spi::connect_mut(|mut conn| {
        let res_data: serde_json::Value = match selections[..] {
            [] => Err(GraphQLError::validation("Selection set must not be empty"))?,
            _ => {
                let mut res_data = json!({});
                // Key name to prepared statement name

                for selection in selections.iter() {
                    let maybe_field_def = map.get(selection.name.as_ref());

                    conn = match maybe_field_def {
                        None => Err(GraphQLError::field_not_found(
                            selection.name.as_ref(),
                            &mutation_type_name,
                        ))?,
                        Some(field_def) => match field_def.type_.unmodified_type() {
                            __Type::InsertResponse(_) => {
                                let builder = match to_insert_builder(
                                    field_def,
                                    selection,
                                    &fragment_definitions,
                                    variables,
                                    variable_definitions,
                                ) {
                                    Ok(builder) => builder,
                                    Err(err) => {
                                        return Err(err);
                                    }
                                };

                                let (d, conn) = builder.execute(conn)?;

                                res_data[alias_or_name(selection)] = d;
                                conn
                            }
                            __Type::UpdateResponse(_) => {
                                let builder = match to_update_builder(
                                    field_def,
                                    selection,
                                    &fragment_definitions,
                                    variables,
                                    variable_definitions,
                                ) {
                                    Ok(builder) => builder,
                                    Err(err) => {
                                        return Err(err);
                                    }
                                };

                                let (d, conn) = builder.execute(conn)?;
                                res_data[alias_or_name(selection)] = d;
                                conn
                            }
                            __Type::DeleteResponse(_) => {
                                let builder = match to_delete_builder(
                                    field_def,
                                    selection,
                                    &fragment_definitions,
                                    variables,
                                    variable_definitions,
                                ) {
                                    Ok(builder) => builder,
                                    Err(err) => {
                                        return Err(err);
                                    }
                                };

                                let (d, conn) = builder.execute(conn)?;
                                res_data[alias_or_name(selection)] = d;
                                conn
                            }
                            _ => match field_def.name().as_ref() {
                                introspection::TYPENAME => {
                                    res_data[alias_or_name(selection)] =
                                        serde_json::json!(mutation_type.name());
                                    conn
                                }
                                _ => {
                                    let builder = match to_function_call_builder(
                                        field_def,
                                        selection,
                                        &fragment_definitions,
                                        variables,
                                        variable_definitions,
                                    ) {
                                        Ok(builder) => builder,
                                        Err(err) => {
                                            return Err(err);
                                        }
                                    };

                                    let (d, conn) =
                                        <FunctionCallBuilder as MutationEntrypoint>::execute(
                                            &builder, conn,
                                        )?;
                                    res_data[alias_or_name(selection)] = d;
                                    conn
                                }
                            },
                        },
                    }
                }
                res_data
            }
        };
        Ok(res_data)
    });

    match spi_result {
        Ok(data) => GraphQLResponse {
            data: Omit::Present(data),
            errors: Omit::Omitted,
        },
        Err(err) => {
            ereport!(
                ERROR,
                PgSqlErrorCode::ERRCODE_INTERNAL_ERROR,
                err.to_string()
            );
        }
    }
}

const STACK_DEPTH_LIMIT: u32 = 50;

fn detect_fragment_cycles<'a, 'b, T>(
    fragment_definition: &'b FragmentDefinition<'a, T>,
    visited: &mut HashSet<&'b str>,
    fragment_definitions: &'b [FragmentDefinition<'a, T>],
    stack_depth: u32,
) -> GraphQLResult<()>
where
    T: Text<'a>,
{
    if stack_depth > STACK_DEPTH_LIMIT {
        return Err(GraphQLError::validation(format!(
            "Fragment cycle depth is greater than {STACK_DEPTH_LIMIT}"
        )));
    }
    if visited.contains(fragment_definition.name.as_ref()) {
        return Err(GraphQLError::validation("Found a cycle between fragments"));
    } else {
        visited.insert(fragment_definition.name.as_ref());
    }
    detect_fragment_cycles_in_selection_set(
        &fragment_definition.selection_set,
        visited,
        fragment_definitions,
        stack_depth + 1,
    )?;

    visited.remove(fragment_definition.name.as_ref());
    Ok(())
}

fn detect_fragment_cycles_in_selection_set<'a, 'b, T>(
    selection_set: &'b SelectionSet<'a, T>,
    visited: &mut HashSet<&'b str>,
    fragment_definitions: &'b [FragmentDefinition<'a, T>],
    stack_depth: u32,
) -> GraphQLResult<()>
where
    T: Text<'a>,
{
    if stack_depth > STACK_DEPTH_LIMIT {
        return Err(GraphQLError::validation(format!(
            "Fragment cycle depth is greater than {STACK_DEPTH_LIMIT}"
        )));
    }
    for selection in &selection_set.items {
        match selection {
            Selection::Field(field) => {
                detect_fragment_cycles_in_selection_set(
                    &field.selection_set,
                    visited,
                    fragment_definitions,
                    stack_depth + 1,
                )?;
            }
            Selection::FragmentSpread(fragment_spread) => {
                for fd in fragment_definitions {
                    if fd.name == fragment_spread.fragment_name {
                        detect_fragment_cycles(fd, visited, fragment_definitions, stack_depth + 1)?;
                        break;
                    }
                }
            }
            Selection::InlineFragment(inline_fragment) => {
                detect_fragment_cycles_in_selection_set(
                    &inline_fragment.selection_set,
                    visited,
                    fragment_definitions,
                    stack_depth + 1,
                )?;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod selection_depth_tests {
    use super::*;
    use graphql_parser::query::parse_query;

    fn run_test_case(query: &str, accept_query: bool) {
        let doc = parse_query::<&str>(query).expect("query parses");
        let mut selection_set = None;
        let mut fragment_defs = vec![];
        for def in doc.definitions {
            match def {
                Definition::Operation(OperationDefinition::SelectionSet(s)) => {
                    selection_set = Some(s)
                }
                Definition::Fragment(fd) => fragment_defs.push(fd),
                _ => {}
            }
        }
        let selection_set = selection_set.expect("anonymous selection set operation");
        let result = validate_selection_depth(&selection_set, &fragment_defs, 1);
        if accept_query {
            assert!(result.is_ok());
        } else {
            assert!(result.is_err());
        }
    }

    #[test]
    fn test_queries_below_max_depth_are_accepted() {
        for depth in 1..MAX_SELECTION_DEPTH {
            let query = &generate_nested_query(depth);
            run_test_case(query, true);
        }
    }

    #[test]
    fn test_queries_above_max_depth_are_rejected() {
        let query = &generate_nested_query(MAX_SELECTION_DEPTH);
        run_test_case(query, false);

        let query = &generate_nested_query(MAX_SELECTION_DEPTH + 1);
        run_test_case(query, false);
    }

    #[test]
    fn test_fragment_spread_nesting_counts_towards_depth() {
        // Every split of the combined depth between aField and fragField:
        // total just below the limit is accepted, ...
        let accepted_total = MAX_SELECTION_DEPTH - 1;
        for a_field_depth in 1..accepted_total {
            let frag_field_depth = accepted_total - a_field_depth;
            let query = &generate_nested_query_via_fragment_spread(a_field_depth, frag_field_depth);
            run_test_case(query, true);
        }

        // ... and total at the limit is rejected, regardless of the split.
        let rejected_total = MAX_SELECTION_DEPTH;
        for a_field_depth in 1..rejected_total {
            let frag_field_depth = rejected_total - a_field_depth;
            let query = &generate_nested_query_via_fragment_spread(a_field_depth, frag_field_depth);
            run_test_case(query, false);
        }
    }

    #[test]
    fn test_inline_fragment_nesting_counts_towards_depth() {
        let accepted_total = MAX_SELECTION_DEPTH - 1;
        for a_field_depth in 1..accepted_total {
            let frag_field_depth = accepted_total - a_field_depth;
            let query = &generate_nested_query_via_inline_fragment(a_field_depth, frag_field_depth);
            run_test_case(query, true);
        }

        let rejected_total = MAX_SELECTION_DEPTH;
        for a_field_depth in 1..rejected_total {
            let frag_field_depth = rejected_total - a_field_depth;
            let query = &generate_nested_query_via_inline_fragment(a_field_depth, frag_field_depth);
            run_test_case(query, false);
        }
    }

    #[test]
    fn test_fragment_spread_and_inline_fragment_nesting_counts_towards_depth() {
        let accepted_total = MAX_SELECTION_DEPTH - 1;
        for a_field_depth in 1..accepted_total {
            let frag_field_depth = accepted_total - a_field_depth;
            let query = &generate_nested_query_via_fragment_and_inline_fragment(
                a_field_depth,
                frag_field_depth,
            );
            run_test_case(query, true);
        }

        let rejected_total = MAX_SELECTION_DEPTH;
        for a_field_depth in 1..rejected_total {
            let frag_field_depth = rejected_total - a_field_depth;
            let query = &generate_nested_query_via_fragment_and_inline_fragment(
                a_field_depth,
                frag_field_depth,
            );
            run_test_case(query, false);
        }
    }

    fn generate_nested_query(depth: u32) -> String {
        let mut inner = "{ aField }".to_string();
        for _ in 0..depth - 1 {
            inner = format!("{{ aField {inner} }}");
        }
        inner
    }

    fn generate_nested_fragment_body(depth: u32) -> String {
        let mut inner = "{ fragField }".to_string();
        for _ in 0..depth - 1 {
            inner = format!("{{ fragField {inner} }}");
        }
        inner
    }

    // Wraps `inner` in `count` layers of `{ field_name { fieldName ... } }`.
    fn wrap_field(field_name: &str, count: u32, inner: &str) -> String {
        let mut result = inner.to_string();
        for _ in 0..count {
            result = format!("{{ {field_name} {result} }}");
        }
        result
    }

    // query { aField { aField { ... { ...fragFields } ... } } }
    // fragment fragFields on Frag { fragField { fragField { ... } } }
    fn generate_nested_query_via_fragment_spread(
        a_field_depth: u32,
        frag_field_depth: u32,
    ) -> String {
        format!(
            "{} fragment fragFields on Frag {}",
            wrap_field("aField", a_field_depth, "{ ...fragFields }"),
            generate_nested_fragment_body(frag_field_depth)
        )
    }

    // query { aField { aField { ... { ... on Frag { fragField { ... } } } ... } } }
    fn generate_nested_query_via_inline_fragment(
        a_field_depth: u32,
        frag_field_depth: u32,
    ) -> String {
        wrap_field(
            "aField",
            a_field_depth,
            &format!(
                "{{ ... on Frag {} }}",
                generate_nested_fragment_body(frag_field_depth)
            ),
        )
    }

    // query { aField { aField { ... { ...fragFields } ... } } }
    // fragment fragFields on Frag { ... on Frag { fragField { ... } } }
    fn generate_nested_query_via_fragment_and_inline_fragment(
        a_field_depth: u32,
        frag_field_depth: u32,
    ) -> String {
        format!(
            "{} fragment fragFields on Frag {{ ... on Frag {} }}",
            wrap_field("aField", a_field_depth, "{ ...fragFields }"),
            generate_nested_fragment_body(frag_field_depth)
        )
    }
}
