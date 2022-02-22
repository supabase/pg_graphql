create function graphql.is_array(regtype)
    returns boolean
    immutable
    language sql
as
$$
    select pg_catalog.format_type($1, null) like '%[]'
$$;
