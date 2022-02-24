create or replace function graphql.build_heartbeat_query(
    ast jsonb
)
    returns text
    language sql
as $$
    select format('select to_jsonb( now() at time zone %L );', 'utc');
$$;
