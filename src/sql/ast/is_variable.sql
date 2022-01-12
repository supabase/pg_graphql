create or replace function graphql.is_variable(field jsonb)
    returns boolean
    immutable
    strict
    language sql
as $$
    select (field ->> 'kind') = 'Variable'
$$;
