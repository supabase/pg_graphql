use std::collections::HashMap;

use graphql_parser::query::{
    Field, FragmentDefinition, FragmentSpread, InlineFragment, Selection, SelectionSet, Text,
    TypeCondition,
};
use itertools::Itertools;

use crate::{__Field, __Type, ___Type, field_map};

#[derive(Debug)]
pub enum ExpansionError {
    FragmentNotFound(String),
    FieldNotFound(String, String),
}

/// Recursively expands a vec of selections into a linear list
/// of fields at each level, including inlining fields from fragment
/// spreads and inline fragments.
pub fn expand<'a, 'b, T>(
    parent_field_type: &__Type,
    selections: Vec<Selection<'a, T>>,
    fragment_definitions: &'b Vec<FragmentDefinition<'a, T>>,
) -> Result<Vec<Field<'a, T>>, ExpansionError>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
{
    let parent_field_type = parent_field_type.unmodified_type();
    let mut fields = vec![];
    let field_to_type = field_map(&parent_field_type);
    for selection in selections {
        match selection {
            Selection::Field(field) => {
                let field = expand_field(
                    &parent_field_type,
                    field,
                    &field_to_type,
                    fragment_definitions,
                )?;
                fields.push(field);
            }
            Selection::FragmentSpread(fragment_spread) => {
                let fragment_fields = expand_fragment_spread(
                    &parent_field_type,
                    fragment_spread,
                    fragment_definitions,
                )?;
                for fragment_field in fragment_fields {
                    fields.push(fragment_field);
                }
            }
            Selection::InlineFragment(inline_fragment) => {
                let fragment_fields = expand_inline_fragment(
                    &parent_field_type,
                    inline_fragment,
                    fragment_definitions,
                )?;
                for fragment_field in fragment_fields {
                    fields.push(fragment_field);
                }
            }
        }
    }
    Ok(fields)
}

fn expand_field<'a, T>(
    parent_field_type: &__Type,
    mut field: Field<'a, T>,
    field_to_type: &HashMap<String, __Field>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
) -> Result<Field<'a, T>, ExpansionError>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
{
    let field_type = field_to_type.get(field.name.as_ref()).ok_or({
        let parent_type_name = parent_field_type
            .name()
            .expect("Field: parent field type is either non-null or list type");
        ExpansionError::FieldNotFound(field.name.as_ref().to_string(), parent_type_name)
    })?;
    let mut children = expand(
        &field_type.type_,
        field.selection_set.items,
        fragment_definitions,
    )?;
    let children = children
        .drain(..)
        .map(|child| Selection::Field(child))
        .collect_vec();
    let selection_set = SelectionSet {
        span: field.selection_set.span,
        items: children,
    };
    field.selection_set = selection_set;
    Ok(field)
}

fn expand_fragment_spread<'a, T>(
    parent_field_type: &__Type,
    fragment_spread: FragmentSpread<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
) -> Result<Vec<Field<'a, T>>, ExpansionError>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
{
    let parent_type_name = parent_field_type
        .name()
        .expect("FragmentSpread: parent field type is either non-null or list type");
    let fragment_definition = get_fragment_definition(
        fragment_definitions,
        fragment_spread.fragment_name,
        parent_type_name.as_str(),
    )?;
    let fragment_fields = expand(
        parent_field_type,
        fragment_definition.selection_set.items.clone(),
        fragment_definitions,
    )?;
    Ok(fragment_fields)
}

fn expand_inline_fragment<'a, T>(
    parent_field_type: &__Type,
    inline_fragment: InlineFragment<'a, T>,
    fragment_definitions: &Vec<FragmentDefinition<'a, T>>,
) -> Result<Vec<Field<'a, T>>, ExpansionError>
where
    T: Text<'a> + Eq + AsRef<str> + Clone,
{
    let parent_type_name = parent_field_type
        .name()
        .expect("InlineFragment: parent field type is either non-null or list type");
    let inline_fragment_applies: bool = match &inline_fragment.type_condition {
        Some(infrag) => match infrag {
            TypeCondition::On(infrag_name) => infrag_name.as_ref() == parent_type_name,
        },
        None => true,
    };
    Ok(if inline_fragment_applies {
        expand(
            parent_field_type,
            inline_fragment.selection_set.items.clone(),
            fragment_definitions,
        )?
    } else {
        vec![]
    })
}

fn get_fragment_definition<'a, 'b, T>(
    fragment_definitions: &'b [FragmentDefinition<'a, T>],
    fragment_name: T::Value,
    type_name: &str,
) -> Result<&'b FragmentDefinition<'a, T>, ExpansionError>
where
    T: Text<'a> + Eq + AsRef<str>,
{
    fragment_definitions
        .iter()
        .find(|fd| {
            if fd.name != fragment_name {
                false
            } else {
                match &fd.type_condition {
                    TypeCondition::On(type_cond_name) => type_cond_name.as_ref() == type_name,
                }
            }
        })
        .ok_or(ExpansionError::FragmentNotFound(format!(
            "Fragment `{:?}` on type `{}` not found",
            fragment_name, type_name
        )))
}
