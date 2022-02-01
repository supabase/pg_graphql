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


create view graphql.entity_column as
    select
        e.entity,
        pa.attname as column_name,
        pa.atttypid::regtype as column_type,
        pa.attnotnull as is_not_null,
        pa.attnum as column_attribute_num
    from
        graphql.entity e
        join pg_attribute pa
            on e.entity = pa.attrelid
    where
        pa.attnum > 0
        and not pa.attisdropped
    order by
        entity,
        attnum;


create view graphql.entity_unique_columns as
    select distinct
        ec.entity,
        array_agg(ec.column_name order by array_position(pi.indkey, ec.column_attribute_num)) unique_column_sets
    from
        graphql.entity_column ec
        join pg_index pi
            on ec.entity = pi.indrelid
            and ec.column_attribute_num = any(pi.indkey)
    where
        pi.indisunique
        and pi.indisready
        and pi.indisvalid
        and pi.indpred is null -- exclude partial indexes
    group by
        ec.entity;
