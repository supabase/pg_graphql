create or replace function graphql.cache_key(role regrole, ast jsonb, variables jsonb)
    returns text
    language sql
    immutable
as $$
    select
        -- Different roles may have different levels of access
        graphql.sha1(
            $1::text
            -- Parsed query hash
            || ast::text
            || graphql.cache_key_variable_component(variables)
        )
$$;
