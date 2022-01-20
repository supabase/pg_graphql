create view graphql.relationship as
    with rels as materialized (
        select
            const.conname as constraint_name,
            e.entity as local_entity,
            array_agg(local_.attname::text order by l.col_ix asc) as local_columns,
            'MANY'::graphql.cardinality as local_cardinality,
            const.confrelid::regclass as foreign_entity,
            array_agg(ref_.attname::text order by r.col_ix asc) as foreign_columns,
            'ONE'::graphql.cardinality as foreign_cardinality
        from
            graphql.entity e
            join pg_constraint const
                on const.conrelid = e.entity
            join pg_attribute local_
                on const.conrelid = local_.attrelid
                and local_.attnum = any(const.conkey)
            join pg_attribute ref_
                on const.confrelid = ref_.attrelid
                and ref_.attnum = any(const.confkey),
            unnest(const.conkey) with ordinality l(col, col_ix)
            join unnest(const.confkey) with ordinality r(col, col_ix)
                on l.col_ix = r.col_ix
        where
            const.contype = 'f'
        group by
            e.entity,
            const.conname,
            const.confrelid
    )
    select constraint_name, local_entity, local_columns, local_cardinality, foreign_entity, foreign_columns, foreign_cardinality from rels
    union all
    select constraint_name, foreign_entity, foreign_columns, foreign_cardinality, local_entity, local_columns, local_cardinality from rels;
