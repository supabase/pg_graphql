create or replace function graphql.is_literal(field jsonb)
    returns boolean
    immutable
    strict
    language sql
as $$
    select not graphql.is_variable(field)
$$;
