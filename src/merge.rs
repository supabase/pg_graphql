use graphql_parser::query::{Field, Text};
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
