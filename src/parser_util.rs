use crate::graphql::{__InputValue, __Type, ___Type};
use graphql_parser::query::*;

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
        Selection::InlineFragment(_) => {
            return Err("inline fragments not yet handled".to_string());
        }
    }

    Ok(selections)
}

pub fn to_json<'a, T>(
    graphql_value: &Value<'a, T>,
    variables: &serde_json::Value,
) -> Result<serde_json::Value, String>
where
    T: Text<'a> + AsRef<str>,
{
    use serde_json::value::Number;
    use serde_json::Map;
    use serde_json::Value as JsonValue;

    let result = match graphql_value {
        Value::Null => JsonValue::Null,
        Value::Boolean(x) => JsonValue::Bool(*x),
        // Why is as_i64 optional?
        Value::Int(x) => {
            let val = x.as_i64();
            match val {
                Some(num) => JsonValue::Number(Number::from(num)),
                None => return Err("Invalid Int input".to_string()),
            }
        }
        Value::Float(x) => {
            let val = Number::from_f64(*x);
            match val {
                Some(num) => JsonValue::Number(num),
                None => return Err("Invalid Float input".to_string()),
            }
        }
        Value::String(x) => JsonValue::String(x.to_owned()),
        Value::Enum(x) => JsonValue::String(x.as_ref().to_string()),
        Value::List(x_arr) => {
            let mut out_arr: Vec<JsonValue> = vec![];
            for x in x_arr {
                let val = to_json(x, variables)?;
                out_arr.push(val);
            }
            JsonValue::Array(out_arr)
        }
        Value::Object(obj) => {
            let mut out_map: Map<String, JsonValue> = Map::new();
            for (key, graphql_val) in obj.iter() {
                let val = to_json(graphql_val, variables)?;
                out_map.insert(key.as_ref().to_string(), val);
            }
            JsonValue::Object(out_map)
        }
        Value::Variable(var_name) => variables
            .get(var_name.as_ref())
            .unwrap_or(&JsonValue::Null)
            .to_owned(),
    };
    Ok(result)
}

pub fn validate_arg_from_type(
    type_: &__Type,
    value: &serde_json::Value,
) -> Result<serde_json::Value, String> {
    use crate::graphql::Scalar;
    use serde_json::Value as JsonValue;

    let res = match type_ {
        __Type::Scalar(scalar) => {
            match scalar {
                Scalar::String => match value {
                    JsonValue::Null | JsonValue::String(_) => value.clone(),
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Int => match value {
                    JsonValue::Null => value.clone(),
                    JsonValue::Number(x) => match x.is_i64() {
                        true => value.clone(),
                        false => return Err(format!("Invalid input for {:?} type", scalar)),
                    },
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Float => match value {
                    JsonValue::Null => value.clone(),
                    JsonValue::Number(x) => match x.is_f64() || x.is_i64() {
                        true => value.clone(),
                        false => return Err(format!("Invalid input for {:?} type", scalar)),
                    },
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Boolean => match value {
                    JsonValue::Null | JsonValue::Bool(_) => value.clone(),
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::Date => {
                    match value {
                        // XXX: future - validate date here
                        JsonValue::Null | JsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::Time => {
                    match value {
                        // XXX: future - validate time here
                        JsonValue::Null | JsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::Datetime => {
                    match value {
                        // XXX: future - validate datetime here
                        JsonValue::Null | JsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::BigInt => match value {
                    JsonValue::Null | JsonValue::String(_) | JsonValue::Number(_) => value.clone(),
                    _ => return Err(format!("Invalid input for {:?} type", scalar)),
                },
                Scalar::UUID => {
                    match value {
                        // XXX: future - validate uuid here
                        JsonValue::Null | JsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::JSON => {
                    match value {
                        // XXX: future - validate json here
                        JsonValue::Null | JsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::Cursor => {
                    match value {
                        // XXX: future - validate cursor here
                        JsonValue::Null | JsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
                Scalar::ID => {
                    match value {
                        // XXX: future - validate cursor here
                        JsonValue::Null | JsonValue::String(_) => value.clone(),
                        _ => return Err(format!("Invalid input for {:?} type", scalar)),
                    }
                }
            }
        }
        __Type::Enum(enum_) => match value {
            JsonValue::Null => value.clone(),
            JsonValue::String(user_input_string) => {
                let matches_enum_value = enum_
                    .enum_values(true)
                    .into_iter()
                    .flatten()
                    .find(|x| x.name().as_str() == user_input_string);
                match matches_enum_value {
                    Some(_) => value.clone(),
                    None => {
                        return Err(format!("Invalid input for {} type", enum_.name().unwrap()))
                    }
                }
            }
            _ => return Err(format!("Invalid input for {} type", enum_.name().unwrap())),
        },
        __Type::OrderBy(enum_) => match value {
            JsonValue::Null => value.clone(),
            JsonValue::String(user_input_string) => {
                let matches_enum_value = enum_
                    .enum_values(true)
                    .into_iter()
                    .flatten()
                    .find(|x| x.name().as_str() == user_input_string);
                match matches_enum_value {
                    Some(_) => value.clone(),
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
                JsonValue::Null => value.clone(),
                JsonValue::Array(input_arr) => {
                    let mut output_arr = vec![];
                    for input_elem in input_arr {
                        let out_elem = validate_arg_from_type(&inner_type, input_elem)?;
                        output_arr.push(out_elem);
                    }
                    JsonValue::Array(output_arr)
                }
                _ => {
                    // Single elements must be coerced to a single element list
                    let out_elem = validate_arg_from_type(&inner_type, value)?;
                    JsonValue::Array(vec![out_elem])
                }
            }
        }
        __Type::NonNull(nonnull_type) => {
            let inner_type: __Type = *nonnull_type.type_.clone();
            let out_elem = validate_arg_from_type(&inner_type, value)?;
            match out_elem {
                JsonValue::Null => return Err("Invalid input for NonNull type".to_string()),
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
    value: &serde_json::Value,
) -> Result<serde_json::Value, String> {
    use crate::graphql::__TypeKind;
    use serde_json::Map;
    use serde_json::Value as JsonValue;

    let input_type_name = input_type.name().unwrap_or_default();

    //let allowed_kinds = vec![__TypeKind::INPUT_OBJECT, __TypeKind::ENUM];
    //if allowed_kinds.contains(&input_type.kind()) {

    if input_type.kind() != __TypeKind::INPUT_OBJECT {
        return Err(format!("Invalid input type {}", input_type_name));
    }

    let res = match value {
        JsonValue::Null => value.clone(),
        JsonValue::Object(input_obj) => {
            let mut out_map: Map<String, JsonValue> = Map::new();
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

                let out_val = match input_obj.get(&obj_field_key) {
                    None => validate_arg_from_type(&obj_field_type, &JsonValue::Null)?,
                    Some(x) => validate_arg_from_type(&obj_field_type, x)?,
                };
                out_map.insert(obj_field_key, out_val);
            }
            JsonValue::Object(out_map)
        }
        _ => return Err(format!("Invalid input for {} type", input_type_name)),
    };
    Ok(res)
}
