create or replace function graphql.value_literal(ast jsonb)
    returns text
    immutable
    language sql
as $$
    select ast -> 'value' ->> 'value';
$$;
