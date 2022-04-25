create or replace function graphql.cache_key(
    role regrole,
    schemas text[],
    schema_version int,
    ast jsonb,
    variables jsonb
)
    returns text
    language sql
    immutable
as $$
    select
        -- Different roles may have different levels of access
        md5(
            $1::text
            || $2::text
            || $3::text
            -- Parsed query hash
            || ast::text
            || graphql.cache_key_variable_component(variables)
        )
$$;
