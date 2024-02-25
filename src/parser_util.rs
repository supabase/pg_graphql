use crate::graphql::{EnumSource, __InputValue, __Type, ___Type};
use crate::gson;
use graphql_parser::query::*;
use std::collections::HashMap;

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
