create materialized view graphql.entity as
    select
        oid::regclass as entity
    from
        pg_class
    where
        relkind = ANY (ARRAY['r', 'p'])
        and not relnamespace = ANY (ARRAY[
            'information_schema'::regnamespace,
            'pg_catalog'::regnamespace,
            'graphql'::regnamespace
        ]);
