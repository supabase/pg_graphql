create or replace function graphql.value_literal(ast jsonb)
    returns text
    immutable
    language sql
as $$
    select ast -> 'value' ->> 'value';
$$;

create or replace function graphql.value_literal_is_null(ast jsonb)
    returns bool
    immutable
    language sql
as $$
    select (ast -> 'value' ->> 'kind') = 'NullValue';
$$;
