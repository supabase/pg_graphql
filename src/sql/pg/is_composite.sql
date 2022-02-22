create function graphql.is_composite(regtype)
    returns boolean
    immutable
    language sql
as
$$
    select typrelid > 0 from pg_catalog.pg_type where oid = $1;
$$;
