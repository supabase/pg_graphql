use std::collections::{HashMap, HashSet};

use crate::builder::{
    to_connection_builder, to_delete_builder, to_function_call_builder, to_insert_builder,
    to_node_builder, to_update_builder, ConnectionBuilder, DeleteBuilder, FunctionCallBuilder,
    InsertBuilder, NodeBuilder, UpdateBuilder,
};
use crate::context::get_one_readonly;
use crate::graphql::__Field;
use crate::params::{BinderBuilder, ParamBinder};
use crate::parser_util::{alias_or_name, normalize_selection_set};
use crate::pg_client::PgClient;
use crate::transpile::{MutationEntrypoint, QueryEntrypoint};
use crate::{
    ErrorMessage, GraphQLResponse, __Schema,
    graphql::{__Type, ___Field, ___Type, field_map},
};
use graphql_engine::omit::Omit;
use graphql_parser::query::{
    Definition, Document, Field, FragmentDefinition, Mutation, OperationDefinition, Query,
    Selection, SelectionSet, Text, VariableDefinition,
};
use itertools::Itertools;
use pgrx::spi::SpiClient;
use serde_json::{json, Value};

#[allow(non_snake_case)]
pub fn resolve_inner<
    'a,
    T,
    C: PgClient<Args = P::Args>,
    B: BinderBuilder<Binder = P>,
    P: ParamBinder,
>(
    client: &C,
    binder_builder: &B,
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

    for fd in &fragment_defs {
        match detect_fragment_cycles(fd, &mut HashSet::new(), &fragment_defs, 1) {
            Ok(()) => {}
            Err(message) => {
                return GraphQLResponse {
                    data: Omit::Omitted,
                    errors: Omit::Present(vec![ErrorMessage { message }]),
                }
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
        Some(op) => match op {
            OperationDefinition::Query(query) => resolve_query::<T, C, B, P>(
                client,
                binder_builder,
                query,
                schema,
                variables,
                fragment_defs,
            ),
            OperationDefinition::SelectionSet(selection_set) => {
                resolve_selection_set::<T, C, B, P>(
                    client,
                    binder_builder,
                    selection_set,
                    schema,
                    variables,
                    fragment_defs,
                    &vec![],
                )
            }
            OperationDefinition::Mutation(mutation) => resolve_mutation::<T, C, B, P>(
                client,
                binder_builder,
                mutation,
                schema,
                variables,
                fragment_defs,
            ),
            OperationDefinition::Subscription(_) => GraphQLResponse {
                data: Omit::Omitted,
                errors: Omit::Present(vec![ErrorMessage {
                    message: "Subscriptions are not supported".to_string(),
                }]),
            },
        },
    }
}

fn resolve_query<'a, T, C: PgClient<Args = P::Args>, B: BinderBuilder<Binder = P>, P: ParamBinder>(
    client: &C,
    binder_builder: &B,
    query: Query<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
    let variable_definitions = &query.variable_definitions;
    resolve_selection_set::<T, C, B, P>(
        client,
        binder_builder,
        query.selection_set,
        schema_type,
        variables,
        fragment_definitions,
        variable_definitions,
    )
}

fn resolve_selection_set<
    'a,
    T,
    C: PgClient<Args = P::Args>,
    B: BinderBuilder<Binder = P>,
    P: ParamBinder,
>(
    client: &C,
    binder_builder: &B,
    selection_set: SelectionSet<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
    let query_type = schema_type.query_type();
    let map = field_map(&query_type);

    let query_type_name = query_type.name().expect("query type should have a name");
    let selections = match normalize_selection_set(
        &selection_set,
        &fragment_definitions,
        &query_type_name,
        variables,
        &query_type,
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
                                Ok(builder) => {
                                    match <ConnectionBuilder as QueryEntrypoint<C, B, P>>::execute(
                                        &builder,
                                        client,
                                        binder_builder,
                                    ) {
                                        Ok(d) => {
                                            res_data[alias_or_name(selection)] = d;
                                        }
                                        Err(msg) => res_errors.push(ErrorMessage { message: msg }),
                                    }
                                }
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
                                Ok(builder) => {
                                    match <NodeBuilder as QueryEntrypoint<C, B, P>>::execute(
                                        &builder,
                                        client,
                                        binder_builder,
                                    ) {
                                        Ok(d) => {
                                            res_data[alias_or_name(selection)] = d;
                                        }
                                        Err(msg) => res_errors.push(ErrorMessage { message: msg }),
                                    }
                                }
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
                                    Ok(builder) => match <FunctionCallBuilder as QueryEntrypoint<
                                        C,
                                        B,
                                        P,
                                    >>::execute(
                                        &builder, client, binder_builder
                                    ) {
                                        Ok(d) => {
                                            res_data[alias_or_name(selection)] = d;
                                        }
                                        Err(msg) => res_errors.push(ErrorMessage { message: msg }),
                                    },
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

fn resolve_mutation<
    'a,
    T,
    C: PgClient<Args = P::Args>,
    B: BinderBuilder<Binder = P>,
    P: ParamBinder,
>(
    client: &C,
    binder_builder: &B,
    query: Mutation<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
    let variable_definitions = &query.variable_definitions;
    resolve_mutation_selection_set::<T, C, B, P>(
        client,
        binder_builder,
        query.selection_set,
        schema_type,
        variables,
        fragment_definitions,
        variable_definitions,
    )
}

fn resolve_mutation_selection_set<
    'a,
    T,
    C: PgClient<Args = P::Args>,
    B: BinderBuilder<Binder = P>,
    P: ParamBinder,
>(
    client: &C,
    binder_builder: &B,
    selection_set: SelectionSet<'a, T>,
    schema_type: &__Schema,
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> GraphQLResponse
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
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
        &mutation_type,
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
        execute_mutation_query::<T, C, B, P>(
            client,
            binder_builder,
            conn,
            &selections,
            variables,
            fragment_definitions,
            variable_definitions,
            &map,
            &mutation_type,
        )
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

fn execute_mutation_query<
    'a,
    T,
    C: PgClient<Args = P::Args>,
    B: BinderBuilder<Binder = P>,
    P: ParamBinder,
>(
    client: &C,
    binder_builder: &B,
    mut conn: SpiClient,
    selections: &[Field<'a, T>],
    variables: &Value,
    fragment_definitions: Vec<FragmentDefinition<'a, T>>,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
    map: &HashMap<String, __Field>,
    mutation_type: &__Type,
) -> Result<Value, String>
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
    let mutation_type_name = mutation_type
        .name()
        .expect("mutation type should have a name");
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
                        selection.name, mutation_type_name
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

                            let (d, conn) =
                                <InsertBuilder as MutationEntrypoint<'_, C, B, P>>::execute(
                                    &builder,
                                    client,
                                    binder_builder,
                                    conn,
                                )?;

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

                            let (d, conn) =
                                <UpdateBuilder as MutationEntrypoint<'_, C, B, P>>::execute(
                                    &builder,
                                    client,
                                    binder_builder,
                                    conn,
                                )?;
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

                            let (d, conn) =
                                <DeleteBuilder as MutationEntrypoint<'_, C, B, P>>::execute(
                                    &builder,
                                    client,
                                    binder_builder,
                                    conn,
                                )?;
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

                                let (d, conn) = <FunctionCallBuilder as MutationEntrypoint<
                                    C,
                                    B,
                                    P,
                                >>::execute(
                                    &builder, client, binder_builder, conn
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
}

const STACK_DEPTH_LIMIT: u32 = 50;

fn detect_fragment_cycles<'a, 'b, T>(
    fragment_definition: &'b FragmentDefinition<'a, T>,
    visited: &mut HashSet<&'b str>,
    fragment_definitions: &'b [FragmentDefinition<'a, T>],
    stack_depth: u32,
) -> Result<(), String>
where
    T: Text<'a>,
{
    if stack_depth > STACK_DEPTH_LIMIT {
        return Err(format!(
            "Fragment cycle depth is greater than {STACK_DEPTH_LIMIT}"
        ));
    }
    if visited.contains(fragment_definition.name.as_ref()) {
        return Err("Found a cycle between fragments".to_string());
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
) -> Result<(), String>
where
    T: Text<'a>,
{
    if stack_depth > STACK_DEPTH_LIMIT {
        return Err(format!(
            "Fragment cycle depth is greater than {STACK_DEPTH_LIMIT}"
        ));
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
