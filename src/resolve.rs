use crate::builder::*;
use crate::graphql::*;
use crate::omit::*;
use crate::parser_util::*;
use graphql_parser::query::{
    Definition, Document, FragmentDefinition, Mutation, OperationDefinition, Query, Selection,
    SelectionSet, Text,
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
    T: Text<'a> + Eq + AsRef<str>,
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
                resolve_selection_set(selection_set, schema, variables, fragment_defs)
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
    T: Text<'a> + Eq + AsRef<str>,
{
    resolve_selection_set(
        query.selection_set,
        schema_type,
        variables,
        fragment_definitions,
    )
}

fn resolve_selection_set<'a, 'b, T>(
    selection_set: SelectionSet<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str>,
{
    use crate::graphql::*;

    let query_type = schema_type.query_type();
    let map = query_type.field_map();

    let selections: Vec<graphql_parser::query::Field<T>> = selection_set
        .items
        .into_iter()
        .filter_map(|def| match def {
            Selection::Field(field) => Some(field),
            // TODO, handle fragments
            _ => panic!("only Selections are supported"),
        })
        .collect();

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
                            let type_map = schema_type.type_map();
                            let __type_builder = schema_type.to_type_builder(
                                field_def,
                                selection,
                                &fragment_definitions,
                                None,
                                variables,
                                &type_map,
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
                                let now_jsonb: pgx::JsonB =
                                    pgx::Spi::get_one("select to_jsonb(now())")
                                        .expect("Internal Error: queries should not return null");
                                let now_json = now_jsonb.0;
                                res_data[alias_or_name(selection)] = now_json;
                            }
                            _ => res_errors.push(ErrorMessage {
                                message: "unexpected type found on query object".to_string(),
                            }),
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
    T: Text<'a> + Eq + AsRef<str>,
{
    resolve_mutation_selection_set(
        query.selection_set,
        schema_type,
        variables,
        fragment_definitions,
    )
}

fn resolve_mutation_selection_set<'a, 'b, T>(
    selection_set: SelectionSet<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str>,
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

    let map = mutation_type.field_map();

    let selections: Vec<graphql_parser::query::Field<T>> = selection_set
        .items
        .into_iter()
        .filter_map(|def| match def {
            Selection::Field(field) => Some(field),
            // TODO, handle fragments
            _ => panic!("only Selections are supported"),
        })
        .collect();

    use pgx::prelude::*;
    use pgx_contrib_spiext::subtxn::*;

    let spi_result: Result<serde_json::Value, String> = Spi::connect(|c| {
        //Create subtransaction
        let sub_txn_result: Result<serde_json::Value, String> = c.sub_transaction(|mut xact| {
            let res_data: serde_json::Value = match selections[..] {
                [] => Err("Selection set must not be empty".to_string())?,
                _ => {
                    let mut res_data = json!({});
                    // Key name to prepared statement name

                    for selection in selections.iter() {
                        let maybe_field_def = map.get(selection.name.as_ref());

                        xact = match maybe_field_def {
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
                                    ) {
                                        Ok(builder) => builder,
                                        Err(err) => {
                                            xact.rollback();
                                            return Err(err);
                                        }
                                    };

                                    let (d, next_xact) = builder.execute(xact)?;

                                    res_data[alias_or_name(selection)] = d;
                                    next_xact
                                }
                                __Type::UpdateResponse(_) => {
                                    let builder = match to_update_builder(
                                        field_def,
                                        selection,
                                        &fragment_definitions,
                                        variables,
                                    ) {
                                        Ok(builder) => builder,
                                        Err(err) => {
                                            xact.rollback();
                                            return Err(err);
                                        }
                                    };

                                    let (d, next_xact) = builder.execute(xact)?;
                                    res_data[alias_or_name(selection)] = d;
                                    next_xact
                                }
                                __Type::DeleteResponse(_) => {
                                    let builder = match to_delete_builder(
                                        field_def,
                                        selection,
                                        &fragment_definitions,
                                        variables,
                                    ) {
                                        Ok(builder) => builder,
                                        Err(err) => {
                                            xact.rollback();
                                            return Err(err);
                                        }
                                    };

                                    let (d, next_xact) = builder.execute(xact)?;
                                    res_data[alias_or_name(selection)] = d;
                                    next_xact
                                }
                                _ => match field_def.name().as_ref() {
                                    "__typename" => {
                                        res_data[alias_or_name(selection)] =
                                            serde_json::json!(mutation_type.name());
                                        xact
                                    }
                                    _ => Err(format!(
                                        "unexpected type found on mutation object: {}",
                                        field_def.type_.name().unwrap_or_default()
                                    ))?,
                                },
                            },
                        }
                    }
                    res_data
                }
            };
            Ok(res_data)
        });

        // Spi::connect requires a Result<Option<_>, SpiError>
        // and unwraps the outer result type, panic-ing if it finds an SpiError.
        // to return our own result, we must wrap it in an Result<Option<T>>
        Ok(Some(sub_txn_result))
    })
    .unwrap();

    match spi_result {
        Ok(data) => GraphQLResponse {
            data: Omit::Present(data),
            errors: Omit::Omitted,
        },
        Err(err) => GraphQLResponse {
            data: Omit::Present(serde_json::Value::Null),
            errors: Omit::Present(vec![ErrorMessage { message: err }]),
        },
    }
}
