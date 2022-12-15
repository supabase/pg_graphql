use crate::graphql::{__InputValue, __Type, ___Type};
use crate::gson;
use graphql_parser::query::*;
use std::collections::HashMap;

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
    type_name: &String, // for inline fragments
) -> Result<Vec<&'b Field<'a, T>>, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let mut selections: Vec<&'b Field<'a, T>> = vec![];

    for selection in &selection_set.items {
        let sel = selection;
        match normalize_selection(sel, fragment_definitions, type_name) {
            Ok(sels) => selections.extend(sels),
            Err(err) => return Err(err),
        }
    }
    Ok(selections)
}

/// Normalizes literal selections, fragment spreads, and inline fragments
pub fn normalize_selection<'a, 'b, T>(
    query_selection: &'b Selection<'a, T>,
    fragment_definitions: &'b Vec<FragmentDefinition<'a, T>>,
    type_name: &String, // for inline fragments
) -> Result<Vec<&'b Field<'a, T>>, String>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    let mut selections: Vec<&Field<'a, T>> = vec![];

    match query_selection {
        Selection::Field(field) => {
            selections.push(field);
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
            let frag_selections =
                normalize_selection_set(&frag_def.selection_set, fragment_definitions, type_name);
            match frag_selections {
                Ok(sels) => selections.extend(sels.iter()),
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
                )?;
                selections.extend(infrag_selections.iter());
            }
        }
    }

    Ok(selections)
}

pub fn to_gson<'a, T>(
    graphql_value: &Value<'a, T>,
    variables: &serde_json::Value,
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
                let val = to_gson(x, variables)?;
                out_arr.push(val);
            }
            gson::Value::Array(out_arr)
        }
        Value::Object(obj) => {
            let mut out_map: HashMap<String, gson::Value> = HashMap::new();
            for (key, graphql_val) in obj.iter() {
                let val = to_gson(graphql_val, variables)?;
                out_map.insert(key.as_ref().to_string(), val);
            }
            gson::Value::Object(out_map)
        }
        Value::Variable(var_name) => {
            let var = variables.get(var_name.as_ref());
            match var {
                None => gson::Value::Absent,
                Some(x) => json_to_gson(x),
            }
        }
    };
    Ok(result)
}

pub fn json_to_gson(val: &serde_json::Value) -> gson::Value {
    // TODO
    // use serde_json::Value as JsonValue;
    gson::Value::Absent
}

pub fn validate_arg_from_type(type_: &__Type, value: &gson::Value) -> Result<gson::Value, String> {
    use crate::graphql::Scalar;
    use crate::gson::Number as GsonNumber;
    use crate::gson::Value as GsonValue;

    let res: GsonValue = match type_ {
        __Type::Scalar(scalar) => {
            match scalar {
                Scalar::String => match value {
                    GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => *value,
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Int => match value {
                    GsonValue::Absent => *value,
                    GsonValue::Null => *value,
                    GsonValue::Number(x) => match x {
                        GsonNumber::Integer(_) => *value,
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    },
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Float => match value {
                    GsonValue::Absent => *value,
                    GsonValue::Null => *value,
                    GsonValue::Number(_) => *value,
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Boolean => match value {
                    GsonValue::Absent | GsonValue::Null | GsonValue::Boolean(_) => *value,
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Date => {
                    match value {
                        // XXX: future - validate date here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => *value,
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::Time => {
                    match value {
                        // XXX: future - validate time here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => *value,
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::Datetime => {
                    match value {
                        // XXX: future - validate datetime here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => *value,
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::BigInt => match value {
                    GsonValue::Absent
                    | GsonValue::Null
                    | GsonValue::String(_)
                    | GsonValue::Number(_) => *value,
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::UUID => {
                    match value {
                        // XXX: future - validate uuid here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => *value,
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::JSON => {
                    match value {
                        // XXX: future - validate json here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => *value,
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::Cursor => {
                    match value {
                        // XXX: future - validate cursor here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => *value,
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::ID => {
                    match value {
                        // XXX: future - validate cursor here
                        GsonValue::Absent | GsonValue::Null | GsonValue::String(_) => *value,
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
            }
        }
        __Type::Enum(enum_) => match value {
            GsonValue::Absent => *value,
            GsonValue::Null => *value,
            GsonValue::String(user_input_string) => {
                let matches_enum_value = enum_
                    .enum_values(true)
                    .into_iter()
                    .flatten()
                    .find(|x| x.name().as_str() == user_input_string);
                match matches_enum_value {
                    Some(_) => *value,
                    None => {
                        return Err(format!("Invalid input for {} type", enum_.name().unwrap()))
                    }
                }
            }
            _ => return Err(format!("Invalid input for {} type", enum_.name().unwrap())),
        },
        __Type::OrderBy(enum_) => match value {
            GsonValue::Absent => *value,
            GsonValue::Null => *value,
            GsonValue::String(user_input_string) => {
                let matches_enum_value = enum_
                    .enum_values(true)
                    .into_iter()
                    .flatten()
                    .find(|x| x.name().as_str() == user_input_string);
                match matches_enum_value {
                    Some(_) => *value,
                    None => {
                        return Err(format!("Invalid input for {} type", enum_.name().unwrap()))
                    }
                }
            }
            _ => return Err(format!("Invalid input for {} type", enum_.name().unwrap())),
        },
        __Type::List(list_type) => {
            let inner_type: __Type = *list_type.type_.clone();
            match value {
                GsonValue::Absent => *value,
                GsonValue::Null => *value,
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
        __Type::InsertInput(_) => validate_arg_from_input_object(type_, value)?,
        __Type::UpdateInput(_) => validate_arg_from_input_object(type_, value)?,
        __Type::OrderByEntity(_) => validate_arg_from_input_object(type_, value)?,
        __Type::FilterType(_) => validate_arg_from_input_object(type_, value)?,
        __Type::FilterEntity(_) => validate_arg_from_input_object(type_, value)?,
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
        GsonValue::Absent => *value,
        GsonValue::Null => *value,
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
