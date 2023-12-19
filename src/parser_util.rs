use crate::graphql::*;
use crate::gson;
use graphql_parser::Pos;
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

pub fn merge_fields<'a, T, I>(
    target_fields: &mut Vec<Field<'a, T>>,
    next_fields: I,
    type_name: &str,
    field_map: &HashMap<String, __Field>,
) -> Result<(), String>
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
    I: IntoIterator<Item = Field<'a, T>>,
{
    for field in next_fields {
        merge_field(target_fields, field, type_name, field_map)?
    }
    Ok(())
}

pub fn merge_field<'a, T>(
    target_fields: &mut Vec<Field<'a, T>>,
    field: Field<'a, T>,
    type_name: &str,
    field_map: &HashMap<String, __Field>,
) -> Result<(), String>
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
    let Some(matching_field) = target_fields
        .iter_mut()
        .find(|target| alias_or_name(target) == alias_or_name(&field))
    else {
        target_fields.push(field);
        return Ok(());
    };

    can_fields_merge(&matching_field, &field, type_name, field_map)?;

    take_mut::take(matching_field, |matching_field| {
        let mut field = field;

        field.position = field.position.min(matching_field.position);

        field.selection_set.span = min_encapsulating_span(
            field.selection_set.span,
            matching_field.selection_set.span,
        );

        // Subfields will be normalized and properly merged on a later pass.
        field
            .selection_set
            .items
            .extend(matching_field.selection_set.items);

        field
    });

    Ok(())
}

pub fn can_fields_merge<'a, T>(
    field_a: &Field<'a, T>,
    field_b: &Field<'a, T>,
    type_name: &str,
    field_map: &HashMap<String, __Field>,
) -> Result<(), String>
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
    let Some(_field_a) = field_map.get(field_a.name.as_ref()) else {
        return Err(format!(
            "Unknown field '{}' on type '{}'",
            field_a.name.as_ref(),
            &type_name
        ));
    };
    let Some(_field_b) = field_map.get(field_b.name.as_ref()) else {
        return Err(format!(
            "Unknown field '{}' on type '{}'",
            field_b.name.as_ref(),
            &type_name
        ));
    };

    has_same_type_shape(
        &alias_or_name(field_a),
        type_name,
        &_field_a.type_,
        &_field_b.type_,
    )?;
    
    if field_a.name != field_b.name {
        return Err(format!(
            "Fields '{}' conflict because '{}' and '{}' are different fields",
            alias_or_name(field_a),
            field_a.name.as_ref(),
            field_b.name.as_ref(),
        ));
    }
    
    for (arg_a_name, arg_a_value) in field_a.arguments.iter() {
        let arg_b_value = field_b.arguments.iter().find_map(|(name, value)|
            if name == arg_a_name {
                Some(value)
            } else {
                None
            });
        let args_match = match arg_b_value {
            None => false,
            Some(arg_b_value) => arg_b_value == arg_a_value,
        };
        if !args_match {
            return Err(format!(
                "Fields '{}' conflict because they have differing arguments",
                alias_or_name(field_a),
            ));
        }
    }
    
    Ok(())
}

pub fn has_same_type_shape(
    field_name: &str,
    type_name: &str,
    type_a: &__Type,
    type_b: &__Type,
) -> Result<(), String> {
    let mut type_a = type_a;
    let mut type_b = type_b;

    if matches!(type_a, __Type::NonNull(_)) || matches!(type_b, __Type::NonNull(_)) {
        if let (__Type::NonNull(nullable_type_a), __Type::NonNull(nullable_type_b)) =
            (type_a, type_b)
        {
            type_a = nullable_type_a.type_.as_ref();
            type_b = nullable_type_b.type_.as_ref();
        } else {
            return Err(format!(
                "Fields '{}' conflict because only one is non nullable",
                field_name,
            ));
        }
    }

    if matches!(type_a, __Type::List(_)) || matches!(type_b, __Type::List(_)) {
        if let (__Type::List(list_type_a), __Type::List(list_type_b)) = (type_a, type_b) {
            type_a = list_type_a.type_.as_ref();
            type_b = list_type_b.type_.as_ref();
        } else {
            return Err(format!(
                "Fields '{}' conflict because only one is a list type",
                field_name,
            ));
        }

        return has_same_type_shape(field_name, type_name, type_a, type_b);
    }

    if matches!(type_a, __Type::Enum(_))
        || matches!(type_b, __Type::Enum(_))
        || matches!(type_a, __Type::Scalar(_))
        || matches!(type_b, __Type::Scalar(_))
    {
        return if type_a == type_b {
            Ok(())
        } else {
            Err(format!(
                "Fields '{}' conflict due to mismatched types",
                field_name,
            ))
        };
    }
    
    // TODO handle composite types?

    // Subfield type shapes will be checked on a later pass.
    Ok(())
}

pub fn min_encapsulating_span(a: (Pos, Pos), b: (Pos, Pos)) -> (Pos, Pos) {
    (a.0.min(b.0), a.1.max(b.1))
}

pub fn normalize_selection_set<'a, T>(
    selection_set: &SelectionSet<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    type_name: &String,            // for inline fragments
    variables: &serde_json::Value, // for directives
    field_type: &__Type,
) -> Result<Vec<Field<'a, T>>, String>
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
    let mut normalized_fields: Vec<Field<'a, T>> = vec![];

    let field_map = field_map(&field_type.unmodified_type());

    for selection in &selection_set.items {
        match normalize_selection(
            selection,
            fragment_definitions,
            type_name,
            variables,
            field_type,
        ) {
            Ok(fields) => merge_fields(&mut normalized_fields, fields, type_name, &field_map)?,
            Err(err) => return Err(err),
        }
    }
    Ok(normalized_fields)
}

/// Combines @skip and @include
pub fn selection_is_skipped<'a, T>(
    query_selection: &Selection<'a, T>,
    variables: &serde_json::Value,
) -> Result<bool, String>
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug,
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
pub fn normalize_selection<'a, T>(
    query_selection: &Selection<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
    type_name: &String,            // for inline fragments
    variables: &serde_json::Value, // for directives
    field_type: &__Type,           // for field merging shape check
) -> Result<Vec<Field<'a, T>>, String>
where
    T: Text<'a> + Eq + AsRef<str> + std::fmt::Debug + Clone,
{
    let mut normalized_fields: Vec<Field<'a, T>> = vec![];

    if selection_is_skipped(query_selection, variables)? {
        return Ok(normalized_fields);
    }

    let field_map = field_map(&field_type.unmodified_type());

    match query_selection {
        Selection::Field(field) => {
            merge_field(&mut normalized_fields, field.clone(), type_name, &field_map)?;
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
            let frag_fields = normalize_selection_set(
                &frag_def.selection_set,
                fragment_definitions,
                type_name,
                variables,
                field_type,
            );
            match frag_fields {
                Ok(fields) => merge_fields(&mut normalized_fields, fields, type_name, &field_map)?,
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
                let infrag_fields = normalize_selection_set(
                    &inline_fragment.selection_set,
                    fragment_definitions,
                    type_name,
                    variables,
                    field_type,
                )?;
                merge_fields(&mut normalized_fields, infrag_fields, type_name, &field_map)?;
            }
        }
    }

    Ok(normalized_fields)
}

pub fn to_gson<'a, T>(
    graphql_value: &Value<'a, T>,
    variables: &serde_json::Value,
    variable_definitions: &Vec<VariableDefinition<'a, T>>,
) -> Result<gson::Value, String>
where
    T: Text<'a> + AsRef<str> + std::fmt::Debug,
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
                            .map(|x| x.default_value.as_ref())
                            .flatten();

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
        __Type::Enum(enum_) => match value {
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
                    None => {
                        return Err(format!("Invalid input for {} type", enum_.name().unwrap()))
                    }
                }
            }
            _ => return Err(format!("Invalid input for {} type", enum_.name().unwrap())),
        },
        __Type::OrderBy(enum_) => match value {
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
