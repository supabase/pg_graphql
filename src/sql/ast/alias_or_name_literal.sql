create or replace function graphql.alias_or_name_literal(field jsonb)
    returns text
    language sql
    immutable
    strict
as $$
    select coalesce(field -> 'alias' ->> 'value', field -> 'name' ->> 'value')
$$;
