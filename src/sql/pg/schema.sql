create materialized view graphql.entity as
    select
        pc.oid::regclass as entity
    from
        pg_class pc
        join pg_index pi
            on pc.oid = pi.indrelid
    where
        relkind = ANY (ARRAY['r', 'p'])
        and not relnamespace = ANY (ARRAY[
            'information_schema'::regnamespace,
            'pg_catalog'::regnamespace,
            'graphql'::regnamespace
        ])
        -- require a primary key (for pagination)
        and pi.indisprimary;


create materialized view graphql.entity_column as
    select
        e.entity,
        pa.attname::text as column_name,
        pa.atttypid::regtype as column_type,
        graphql.is_array(pa.atttypid::regtype) is_array,
        graphql.is_composite(pa.atttypid::regtype) is_composite,
        pa.attnotnull as is_not_null,
        not pa.attgenerated = '' as is_generated,
        pg_get_serial_sequence(e.entity::text, pa.attname) is not null as is_serial,
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

create index ix_entity_column_entity_column_name
    on graphql.entity_column(entity, column_name);


create materialized view graphql.entity_unique_columns as
    select distinct
        ec.entity,
        pi.indexrelid::regclass::name index_name,
        array_agg(ec.column_name order by array_position(pi.indkey, ec.column_attribute_num)) unique_column_set
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
        ec.entity,
        pi.indexrelid;


create function graphql.column_set_is_unique(regclass, columns text[])
    returns bool
    language sql
    immutable
as $$
    select exists(
        select
            1
        from
            graphql.entity_unique_columns euc
        where
            euc.entity = $1
            -- unique set is contained by columns list
            and euc.unique_column_set <@ $2
    )
$$;
