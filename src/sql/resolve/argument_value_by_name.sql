create or replace function graphql.argument_value_by_name(name text, ast jsonb)
    returns text
    immutable
    language sql
as $$
    select jsonb_path_query_first(ast, ('$.arguments[*] ? (@.name.value == "' || name ||'")')::jsonpath) -> 'value' ->> 'value';
$$;
