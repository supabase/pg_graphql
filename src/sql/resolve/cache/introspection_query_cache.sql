create table graphql.introspection_query_cache(
    cache_key text primary key, -- equivalent to prepared statement name
    response_data jsonb
);

create or replace function graphql.get_introspection_cache(cache_key text)
    returns jsonb
    security definer
    language sql
as $$
    select
        response_data
    from
        graphql.introspection_query_cache
    where
        cache_key = $1
    limit 1
$$;

create or replace function graphql.set_introspection_cache(cache_key text, response_data jsonb)
    returns void
    security definer
    language sql
as $$
    insert into
        graphql.introspection_query_cache(cache_key, response_data)
    values
        ($1, $2)
    on conflict (cache_key) do nothing;
$$;
