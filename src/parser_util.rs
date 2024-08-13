use crate::graphql::{EnumSource, __InputValue, __Type, ___Type};
use crate::{gson, merge::merge};
use graphql_parser::query::*;
use std::collections::HashMap;
use std::hash::Hash;

pub fn alias_or_name<'a, T>(query_field: &graphql_parser::query::Field<'a, T>) -> String
where
    T: Text<'a> + Eq + AsRef<str>,
{
    query_field
        .alias
        .as_ref()
        .map(|x| x.as_ref().to_string())
        .unwrap_or_else(|| query_field.name.as_ref().to_string())
}

pub fn normalize_selection_set<'a, 'b, T>(
    selection_set: &'b SelectionSet<'a, T>,
    fragment_definitions: &'b Vec<FragmentDefinition<'a, T>>,
    type_name: &String,            // for inline fragments
    variables: &serde_json::Value, // for directives
) -> Result<Vec<Field<'a, T>>, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let mut selections: Vec<Field<'a, T>> = vec![];

    for selection in &selection_set.items {
        let sel = selection;
        match normalize_selection(sel, fragment_definitions, type_name, variables) {
            Ok(sels) => selections.extend(sels),
            Err(err) => return Err(err),
        }
    }
    let selections = merge(selections)?;
    Ok(selections)
}

/// Combines @skip and @include
pub fn selection_is_skipped<'a, 'b, T>(
    query_selection: &'b Selection<'a, T>,
    variables: &serde_json::Value,
) -> Result<bool, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let directives = match query_selection {
        Selection::Field(x) => &x.directives,
        Selection::FragmentSpread(x) => &x.directives,
        Selection::InlineFragment(x) => &x.directives,
    };

    if !directives.is_empty() {
        for directive in directives {
            let directive_name = directive.name.as_ref();
            match directive_name {
                "skip" => {
                    if directive.arguments.len() != 1 {
                        return Err("Incorrect arguments to directive @skip".to_string());
                    }
                    let arg = &directive.arguments[0];
                    if arg.0.as_ref() != "if" {
                        return Err(format!("Unknown argument to @skip: {}", arg.0.as_ref()));
                    }

                    // the argument to @skip(if: <value>)
                    match &arg.1 {
                        Value::Boolean(x) => {
                            if *x {
                                return Ok(true);
                            }
                        }
                        Value::Variable(var_name) => {
                            let var = variables.get(var_name.as_ref());
                            match var {
                                Some(serde_json::Value::Bool(bool_val)) => {
                                    if *bool_val {
                                        // skip immediately
                                        return Ok(true);
                                    }
                                }
                                _ => {
                                    return Err("Value for \"if\" in @skip directive is required"
                                        .to_string());
                                }
                            }
                        }
                        _ => (),
                    }
                }
                "include" => {
                    if directive.arguments.len() != 1 {
                        return Err("Incorrect arguments to directive @include".to_string());
                    }
                    let arg = &directive.arguments[0];
                    if arg.0.as_ref() != "if" {
                        return Err(format!("Unknown argument to @include: {}", arg.0.as_ref()));
                    }

                    // the argument to @include(if: <value>)
                    match &arg.1 {
                        Value::Boolean(x) => {
                            if !*x {
                                return Ok(true);
                            }
                        }
                        Value::Variable(var_name) => {
                            let var = variables.get(var_name.as_ref());
                            match var {
                                Some(serde_json::Value::Bool(bool_val)) => {
                                    if !bool_val {
                                        return Ok(true);
                                    }
                                }
                                _ => {
                                    return Err(
                                        "Value for \"if\" in @include directive is required"
                                            .to_string(),
                                    );
                                }
                            }
                        }
                        _ => (),
                    }
                }
                _ => return Err(format!("Unknown directive {}", directive_name)),
            }
        }
    }
    Ok(false)
}

/// Normalizes literal selections, fragment spreads, and inline fragments
pub fn normalize_selection<'a, 'b, T>(
    query_selection: &'b Selection<'a, T>,
    fragment_definitions: &'b Vec<FragmentDefinition<'a, T>>,
    type_name: &String,            // for inline fragments
    variables: &serde_json::Value, // for directives
) -> Result<Vec<Field<'a, T>>, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
    T::Value: Hash,
{
    let mut selections: Vec<Field<'a, T>> = vec![];

    if selection_is_skipped(query_selection, variables)? {
        return Ok(selections);
    }

    match query_selection {
        Selection::Field(field) => {
            selections.push(field.clone());
        }
        Selection::FragmentSpread(fragment_spread) => {
            let frag_name = &fragment_spread.fragment_name;

            // Fragments can have type conditions
            // https://spec.graphql.org/June2018/#sec-Type-Conditions
            // so we must check the type too...
            let frag_def = match fragment_definitions
                .iter()
                .filter(|x| &x.name == frag_name)
                .find(|x| match &x.type_condition {
                    // TODO match when no type condition is specified?
                    TypeCondition::On(frag_type_name) => frag_type_name.as_ref() == type_name,
                }) {
                Some(frag) => frag,
                None => {
                    return Err(format!(
                        "no fragment named {} on type {}",
                        frag_name.as_ref(),
                        type_name
                    ))
                }
            };

            // TODO handle directives?
            let frag_selections = normalize_selection_set(
                &frag_def.selection_set,
                fragment_definitions,
                type_name,
                variables,
            );
            match frag_selections {
                Ok(sels) => selections.extend(sels),
                Err(err) => return Err(err),
            };
        }
        Selection::InlineFragment(inline_fragment) => {
            let inline_fragment_applies: bool = match &inline_fragment.type_condition {
                Some(infrag) => match infrag {
                    TypeCondition::On(infrag_name) => infrag_name.as_ref() == type_name,
                },
                None => true,
            };

            if inline_fragment_applies {
                let infrag_selections = normalize_selection_set(
                    &inline_fragment.selection_set,
                    fragment_definitions,
                    type_name,
                    variables,
                )?;
                selections.extend(infrag_selections);
            }
        }
    }

    Ok(selections)
}

pub fn to_gson<'a, T>(
    graphql_value: &Value<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<gson::Value, String>
where
    T: Text<'a> + AsRef<str>,
{
    let result = match graphql_value {
        Value::Null => gson::Value::Null,
        Value::Boolean(x) => gson::Value::Boolean(*x),
        Value::Int(x) => {
            let val = x.as_i64();
            match val {
                Some(num) => {
                    let i_val = gson::Number::Integer(num);
                    gson::Value::Number(i_val)
                }
                None => return Err("Invalid Int input".to_string()),
            }
        }
        Value::Float(x) => {
            let val: gson::Number = gson::Number::Float(*x);
            gson::Value::Number(val)
        }
        Value::String(x) => gson::Value::String(x.to_owned()),
        Value::Enum(x) => gson::Value::String(x.as_ref().to_string()),
        Value::List(x_arr) => {
            let mut out_arr: Vec<gson::Value> = vec![];
            for x in x_arr {
                let val = to_gson(x, variables, variable_definitions)?;
                out_arr.push(val);
            }
            gson::Value::Array(out_arr)
        }
        Value::Object(obj) => {
            let mut out_map: HashMap<String, gson::Value> = HashMap::new();
            for (key, graphql_val) in obj.iter() {
                let val = to_gson(graphql_val, variables, variable_definitions)?;
                out_map.insert(key.as_ref().to_string(), val);
            }
            gson::Value::Object(out_map)
        }
        Value::Variable(var_name) => {
            let var = variables.get(var_name.as_ref());
            match var {
                Some(x) => gson::json_to_gson(x)?,
                None => {
                    let variable_default: Option<&graphql_parser::query::Value<'a, T>> =
                        variable_definitions
                            .iter()
                            .find(|var_def| var_def.name.as_ref() == var_name.as_ref())
                            .and_then(|x| x.default_value.as_ref());

                    match variable_default {
                        Some(x) => to_gson(x, variables, variable_definitions)?,
                        None => gson::Value::Absent,
                    }
                }
            }
        }
    };
    Ok(result)
}

pub fn validate_arg_from_type(type_: &__Type, value: &gson::Value) -> Result<gson::Value, String> {
    use crate::graphql::Scalar;
    use crate::gson::Number as GsonNumber;
    use crate::gson::Value as GsonValue;

    let res: GsonValue = match type_ {
        __Type::Scalar(scalar) => {
            match scalar {
                Scalar::String(None) => match value {
                    GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => value.clone(),
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::String(Some(max_length)) => match value {
                    GsonValue::Absent | GsonValue::Null => value.clone(),
                    GsonValue::String(string_content) => {
                        match string_content.len() as i32 > *max_length {
                            false => value.clone(),
                            true => {
                                return Err(format!(
                                    "Invalid input for {} type. Maximum character length {}",
                                    scalar.name().unwrap_or("String".to_string()),
                                    max_length
                                ))
                            }
                        }
                    }
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Int => match value {
                    GsonValue::Absent => value.clone(),
                    GsonValue::Null => value.clone(),
                    GsonValue::Number(GsonNumber::Integer(_)) => value.clone(),
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Float => match value {
                    GsonValue::Absent => value.clone(),
                    GsonValue::Null => value.clone(),
                    GsonValue::Number(_) => value.clone(),
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Boolean => match value {
                    GsonValue::Absent | GsonValue::Null | GsonValue::Boolean(_) => value.clone(),
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Date => {
                    match value {
                        // XXX: future - validate date here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::Time => {
                    match value {
                        // XXX: future - validate time here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::Datetime => {
                    match value {
                        // XXX: future - validate datetime here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::BigInt => match value {
                    GsonValue::Absent
                    | GsonValue::Null
                    | GsonValue::String(_)
                    | GsonValue::Number(_) => value.clone(),
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::UUID => {
                    match value {
                        // XXX: future - validate uuid here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::JSON => {
                    match value {
                        // XXX: future - validate json here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::Cursor => {
                    match value {
                        // XXX: future - validate cursor here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::ID => {
                    match value {
                        // XXX: future - validate cursor here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::BigFloat => match value {
                    GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => value.clone(),
                    _ => {
                        return Err(format!(
                            "Invalid input for {:?} type. String required",
                            scalar
                        ))
                    }
                },
                // No validation possible for unknown types. Lean on postgres for parsing
                Scalar::Opaque => value.clone(),
            }
        }
        __Type::Enum(enum_) => {
            let enum_name = enum_.name().expect("enum type should have a name");
            match value {
                GsonValue::Absent => value.clone(),
                GsonValue::Null => value.clone(),
                GsonValue::String(user_input_string) => {
                    let matches_enum_value = enum_
                        .enum_values(true)
                        .into_iter()
                        .flatten()
                        .find(|x| x.name().as_str() == user_input_string);
                    match matches_enum_value {
                        Some(_) => {
                            match &enum_.enum_ {
                                EnumSource::Enum(e) => e
                                    .directives
                                    .mappings
                                    .as_ref()
                                    // Use mappings if available and mapped
                                    .and_then(|mappings| mappings.get_by_right(user_input_string))
                                    .map(|val| GsonValue::String(val.clone()))
                                    .unwrap_or_else(|| value.clone()),
                                EnumSource::FilterIs => value.clone(),
                                // TODO(or): Do I need to check directives here?
                                EnumSource::TableColumns(_e) => value.clone(),
                                EnumSource::OnConflictTarget(_e) => value.clone(),
                            }
                        }
                        None => return Err(format!("Invalid input for {} type", enum_name)),
                    }
                }
                _ => return Err(format!("Invalid input for {} type", enum_name)),
            }
        }
        __Type::OrderBy(enum_) => {
            let enum_name = enum_.name().expect("order by type should have a name");
            match value {
                GsonValue::Absent => value.clone(),
                GsonValue::Null => value.clone(),
                GsonValue::String(user_input_string) => {
                    let matches_enum_value = enum_
                        .enum_values(true)
                        .into_iter()
                        .flatten()
                        .find(|x| x.name().as_str() == user_input_string);
                    match matches_enum_value {
                        Some(_) => value.clone(),
                        None => return Err(format!("Invalid input for {} type", enum_name)),
                    }
                }
                _ => return Err(format!("Invalid input for {} type", enum_name)),
            }
        }
        __Type::List(list_type) => {
            let inner_type: __Type = *list_type.type_.clone();
            match value {
                GsonValue::Absent => value.clone(),
                GsonValue::Null => value.clone(),
                GsonValue::Array(input_arr) => {
                    let mut output_arr = vec![];
                    for input_elem in input_arr {
                        let out_elem = validate_arg_from_type(&inner_type, input_elem)?;
                        output_arr.push(out_elem);
                    }
                    GsonValue::Array(output_arr)
                }
                _ => {
                    // Single elements must be coerced to a single element list
                    let out_elem = validate_arg_from_type(&inner_type, value)?;
                    GsonValue::Array(vec![out_elem])
                }
            }
        }
        __Type::NonNull(nonnull_type) => {
            let inner_type: __Type = *nonnull_type.type_.clone();
            let out_elem = validate_arg_from_type(&inner_type, value)?;
            match out_elem {
                GsonValue::Absent | GsonValue::Null => {
                    return Err("Invalid input for NonNull type".to_string())
                }
                _ => out_elem,
            }
        }
        __Type::InsertInput(_)
        | __Type::UpdateInput(_)
        | __Type::OrderByEntity(_)
        | __Type::FilterType(_)
        | __Type::FilterEntity(_)
        | __Type::OnConflictInput(_) => validate_arg_from_input_object(type_, value)?,
        _ => {
            return Err(format!(
                "Invalid Type used as input argument {}",
                type_.name().unwrap_or_default()
            ))
        }
    };
    Ok(res)
}

pub fn validate_arg_from_input_object(
    input_type: &__Type,
    value: &gson::Value,
) -> Result<gson::Value, String> {
    use crate::graphql::__TypeKind;
    use crate::gson::Value as GsonValue;

    let input_type_name = input_type.name().unwrap_or_default();

    if input_type.kind() != __TypeKind::INPUT_OBJECT {
        return Err(format!("Invalid input type {}", input_type_name));
    }

    let res: GsonValue = match value {
        GsonValue::Absent => value.clone(),
        GsonValue::Null => value.clone(),
        GsonValue::Object(input_obj) => {
            let mut out_map: HashMap<String, GsonValue> = HashMap::new();
            let type_input_fields: Vec<__InputValue> =
                input_type.input_fields().unwrap_or_default();

            // Confirm that there are no extra keys
            let mut extra_input_keys = vec![];
            for (k, _) in input_obj.iter() {
                if !type_input_fields.iter().map(|x| x.name()).any(|x| x == *k) {
                    extra_input_keys.push(k);
                }
            }
            if !extra_input_keys.is_empty() {
                return Err(format!(
                    "Input for type {} contains extra keys {:?}",
                    input_type_name, extra_input_keys
                ));
            }

            for obj_field in type_input_fields {
                let obj_field_type: __Type = obj_field.type_();
                let obj_field_key: String = obj_field.name();

                match input_obj.get(&obj_field_key) {
                    None => {
                        validate_arg_from_type(&obj_field_type, &GsonValue::Null)?;
                    }
                    Some(x) => {
                        let out_val = validate_arg_from_type(&obj_field_type, x)?;
                        out_map.insert(obj_field_key, out_val);
                    }
                };
            }
            GsonValue::Object(out_map)
        }
        _ => return Err(format!("Invalid input for {} type", input_type_name)),
    };
    Ok(res)
}
