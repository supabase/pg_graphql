use crate::builder::*;
use crate::graphql::*;
use crate::omit::*;
use crate::parser_util::*;
use crate::sql_types::get_one_readonly;
use crate::transpile::{MutationEntrypoint, QueryEntrypoint};
use graphql_parser::query::{
    Definition, Document, FragmentDefinition, Mutation, OperationDefinition, Query, SelectionSet,
    Text, VariableDefinition,
};
use itertools::Itertools;
use serde_json::{json, Value};

#[allow(non_snake_case)]
pub fn resolve_inner<'a, T>(
    document: Document<'a, T>,
    variables: &Value,
    operation_name: &Option<String>,
    schema: &__Schema,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
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

    match maybe_op {
        None => GraphQLResponse {
            data: Omit::Omitted,
            errors: Omit::Present(vec![ErrorMessage {
                message: "Operation not found".to_string(),
            }]),
        },
        Some(op) => match op {
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
        },
    }
}

fn resolve_query<'a, 'b, T>(
    query: Query<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
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
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
    use crate::graphql::*;

    let query_type = schema_type.query_type();
    let map = field_map(&query_type);

    let selections = match normalize_selection_set(
        &selection_set,
        &fragment_definitions,
        &query_type.name().unwrap(),
        variables,
    ) {
        Ok(selections) => selections,
        Err(err) => {
            return GraphQLResponse {
                data: Omit::Omitted,
                errors: Omit::Present(vec![ErrorMessage {
                    message: err.to_string(),
                }]),
            }
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
                                selection.name,
                                query_type.name().unwrap()
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
                                    Err(msg) => res_errors.push(ErrorMessage { message: msg }),
                                },
                                Err(msg) => res_errors.push(ErrorMessage { message: msg }),
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
                                    Err(msg) => res_errors.push(ErrorMessage { message: msg }),
                                },
                                Err(msg) => res_errors.push(ErrorMessage { message: msg }),
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
                                Err(msg) => res_errors.push(ErrorMessage { message: msg }),
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
                                Err(msg) => res_errors.push(ErrorMessage { message: msg }),
                            }
                        }
                        _ => match field_def.name().as_ref() {
                            "__typename" => {
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
                                            Err(msg) => {
                                                res_errors.push(ErrorMessage { message: msg })
                                            }
                                        }
                                    }
                                    Err(msg) => res_errors.push(ErrorMessage { message: msg }),
                                }
                            }
                        },
                    },
                }
            }
            GraphQLResponse {
                data: match res_errors.len() {
                    0 => Omit::Present(res_data),
                    _ => Omit::Present(serde_json::Value::Null),
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
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
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
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
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

    let selections = match normalize_selection_set(
        &selection_set,
        &fragment_definitions,
        &mutation_type.name().unwrap(),
        variables,
    ) {
        Ok(selections) => selections,
        Err(err) => {
            return GraphQLResponse {
                data: Omit::Omitted,
                errors: Omit::Present(vec![ErrorMessage {
                    message: err.to_string(),
                }]),
            }
        }
    };

    use pgrx::prelude::*;

    let spi_result: Result<serde_json::Value, String> = Spi::connect(|mut conn| {
        let res_data: serde_json::Value = match selections[..] {
            [] => Err("Selection set must not be empty".to_string())?,
            _ => {
                let mut res_data = json!({});
                // Key name to prepared statement name

                for selection in selections.iter() {
                    let maybe_field_def = map.get(selection.name.as_ref());

                    conn = match maybe_field_def {
                        None => Err(format!(
                            "Unknown field {:?} on type {}",
                            selection.name,
                            mutation_type.name().unwrap()
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
                                "__typename" => {
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
            ereport!(ERROR, PgSqlErrorCode::ERRCODE_INTERNAL_ERROR, err);
        }
    }
}
