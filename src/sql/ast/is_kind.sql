create type graphql.parser_kind as enum ('ObjectValue', 'ObjectField', 'ListValue');


create or replace function graphql.is_kind(ast jsonb, k graphql.parser_kind)
    returns boolean
    language sql
as $$
    select ast ->> 'kind' = k::text;
$$;
