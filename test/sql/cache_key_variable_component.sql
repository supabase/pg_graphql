-- Confirm returns string, not null
select graphql.cache_key_variable_component('{}');

select graphql.cache_key_variable_component('{"x": 1}');

select graphql.cache_key_variable_component('{"x": "1"}');

-- Matches
select graphql.cache_key_variable_component('{"id": {"eq": 1}}');

select graphql.cache_key_variable_component('{"orderByVal": "DescNullsFirst"}');

select graphql.cache_key_variable_component('{"orderByObj": [{"email": "AscNullsFirst"}]}');

-- Cursors not included
select graphql.cache_key_variable_component(
    variables := '{"afterCursor": "xxxxxx", "other": 1}',
    variable_definitions := '[
        {
            "kind": "VariableDefinition",
            "type": {
                "kind": "NamedType",
                "name": {
                    "kind": "Name",
                    "value": "Cursor"
                }
            },
            "variable": {
                "kind": "Variable",
                "name": {
                    "kind": "Name",
                    "value": "afterCursor"
                }
            },
            "defaultValue": null
        }
    ]'::jsonb
);
