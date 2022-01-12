-- Confirm no match returns string, not null
select graphql.cache_key_variable_component('{}') = '';

-- No matches
select graphql.cache_key_variable_component('{}');

select graphql.cache_key_variable_component('{"x": 1}');

select graphql.cache_key_variable_component('{"x": "1"}');

-- Matches
select graphql.cache_key_variable_component('{"id": {"eq": 1}}');

select graphql.cache_key_variable_component('{"orderByVal": "DescNullsFirst"}');

select graphql.cache_key_variable_component('{"orderByObj": [{"email": "AscNullsFirst"}]}');

select graphql.cache_key_variable_component('{
    "id": {"eq": 1},
    "orderByVal": "DescNullsFirst",
    "orderByObj": [
        {"email": "AscNullsFirst"}
    ]
}');
