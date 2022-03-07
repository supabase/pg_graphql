create function graphql.to_function_name(regproc)
    returns text
    language sql
    stable
as
$$
    select
        proname
    from
        pg_proc
    where
        oid = $1::oid
$$;
