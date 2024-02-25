use graphql_parser::query::{Field, Text, Value};
use indexmap::IndexMap;

use crate::parser_util::alias_or_name;

pub fn merge<'a, 'b, T>(fields: &[Field<'a, T>]) -> Result<Vec<Field<'a, T>>, String>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
{
    let mut merged: IndexMap<String, Field<'a, T>> = IndexMap::new();

    for current_field in fields {
        let response_key = alias_or_name(current_field);
        match merged.get_mut(&response_key) {
            Some(existing_field) => {
                if current_field.name != existing_field.name {
                    return Err(format!(
                        "Fields `{}` and `{}` are different",
                        current_field.name.as_ref(),
                        existing_field.name.as_ref(),
                    ));
                }
                if !same_arguments(&current_field.arguments, &existing_field.arguments) {
                    return Err(format!(
                        "Two fields named `{}` have different arguments",
                        current_field.name.as_ref(),
                    ));
                }
                existing_field
                    .selection_set
                    .items
                    .extend(current_field.selection_set.items.iter().cloned());
            }
            None => {
                merged.insert(response_key, (*current_field).clone());
            }
        }
    }

    let mut fields = vec![];

    for (_, field) in merged {
        fields.push(field);
    }

    Ok(fields)
}

fn same_arguments<'a, 'b, T>(
    arguments_a: &[(T::Value, Value<'a, T>)],
    arguments_b: &[(T::Value, Value<'a, T>)],
) -> bool
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
{
    if arguments_a.len() != arguments_b.len() {
        return false;
    }

    for (arg_a_name, arg_a_val) in arguments_a {
        for (arg_b_name, arg_b_val) in arguments_b {
            if arg_a_name == arg_b_name && arg_a_val != arg_b_val {
                return false;
            }
        }
    }

    true
}
