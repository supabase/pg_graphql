with search_path_oids(schema_oid) as (
    select y::regnamespace::oid from unnest(current_schemas(false)) x(y)
)
select
    jsonb_build_object(
        'config', jsonb_build_object(
            'search_path', current_schemas(false),
            'role', current_role,
            'schema_version', graphql.get_schema_version()
        ),
        'enums', coalesce(
            (
                select
                    jsonb_agg(
                        distinct -- needed?
                        jsonb_build_object(
                            'oid', pt.oid::int,
                            'schema_oid', pt.typnamespace::int,
                            'name', pt.typname,
                            'comment', pg_catalog.obj_description(pt.oid, 'pg_type'),
                            'directives', jsonb_build_object(
                                'name', graphql.comment_directive(pg_catalog.obj_description(pt.oid, 'pg_type')) ->> 'name'
                            ),
                            'values', (
                                select
                                    jsonb_agg(
                                        jsonb_build_object(
                                            'oid', pe.oid::int,
                                            'name', pe.enumlabel,
                                            'sort_order', pe.enumsortorder
                                        )
                                        order by enumsortorder asc
                                    )
                                from
                                    pg_enum pe
                                where
                                    pt.oid = pe.enumtypid
                            ),
                            'permissions', jsonb_build_object(
                                'is_usable', pg_catalog.has_type_privilege(current_user, pt.oid, 'USAGE')
                            )
                        )
                    )
                from
                    pg_enum
                    join pg_type pt
                        on pt.oid = pg_enum.enumtypid
                    join search_path_oids spo
                        on pt.typnamespace = spo.schema_oid
            ),
            jsonb_build_array()
        ),
        'composites', coalesce(
            (
                select
                    jsonb_agg(
                        jsonb_build_object(
                            'oid', pt.oid::int,
                            'schema_oid', pt.typnamespace::int
                        )
                    )
                from
                    pg_type pt
                    join search_path_oids spo
                        on pt.typnamespace = spo.schema_oid
                where
                    pt.typtype = 'c'
            ),
            jsonb_build_array()
        ),
        'schemas', coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'oid', pn.oid::int,
                    'name', pn.nspname::text,
                    'comment', pg_catalog.obj_description(pn.oid, 'pg_namespace'),
                    'directives', jsonb_build_object(
                        'inflect_names', schema_directives.inflect_names
                    ),
                    'tables', coalesce(
                        (
                            select
                                jsonb_agg(
                                    jsonb_build_object(
                                        'oid', pc.oid::int,
                                        'name', pc.relname::text,
                                        'schema', pn.nspname::text,
                                        'comment', pg_catalog.obj_description(pc.oid, 'pg_class'),
                                        'directives', jsonb_build_object(
                                            'inflect_names', schema_directives.inflect_names,
                                            'name', graphql.comment_directive(pg_catalog.obj_description(pc.oid, 'pg_class')) ->> 'name',
                                            'total_count', jsonb_build_object(
                                                'enabled', coalesce(
                                                    (
                                                        graphql.comment_directive(
                                                            pg_catalog.obj_description(pc.oid, 'pg_class')
                                                        ) -> 'totalCount' ->> 'enabled' = 'true'
                                                    ),
                                                    false
                                                )
                                            )
                                        ),
                                        'functions', coalesce(
                                            (
                                                select
                                                    jsonb_agg(
                                                        jsonb_build_object(
                                                            'oid', pp.oid::int,
                                                            'name', pp.proname::text,
                                                            'type_oid', pp.prorettype::oid::int,
                                                            'type_name', pp.prorettype::regtype::text,
                                                            'schema_name', pronamespace::regnamespace::text,
                                                            'comment', pg_catalog.obj_description(pp.oid, 'pg_proc'),
                                                            'directives', jsonb_build_object(
                                                                'inflect_names', schema_directives.inflect_names,
                                                                'name', graphql.comment_directive(pg_catalog.obj_description(pp.oid, 'pg_proc')) ->> 'name'
                                                            ),
                                                            'permissions', jsonb_build_object(
                                                                'is_executable', pg_catalog.has_function_privilege(
                                                                    current_user,
                                                                    pp.oid,
                                                                    'EXECUTE'
                                                                )
                                                            )
                                                        )
                                                    )
                                                from
                                                    pg_catalog.pg_proc pp
                                                where
                                                    pp.pronargs = 1 -- one argument
                                                    and pp.proargtypes[0] = pc.reltype -- first argument is table type
                                                    and pp.proname like '\_%' -- starts with underscore
                                            ),
                                            jsonb_build_array()
                                        ),
                                        'indexes', coalesce(
                                            (
                                                select
                                                    jsonb_agg(
                                                        jsonb_build_object(
                                                            'oid', pi.indexrelid::int,
                                                            'table_oid', pi.indrelid::int,
                                                            'name', pi.indexrelid::regclass::text,
                                                            'column_attnums', coalesce((select array_agg(x.y::int) from unnest(pi.indkey) x(y)), array[]::int[]),
                                                            'is_unique', pi.indisunique,
                                                            'is_primary_key', pi.indisprimary,
                                                            'comment', pg_catalog.obj_description(pi.indexrelid, 'pg_index')
                                                        )
                                                    )
                                                from
                                                    pg_catalog.pg_index pi
                                                where
                                                    pi.indrelid = pc.oid
                                            ),
                                            jsonb_build_array()
                                        ),
                                        'foreign_keys', (
                                            coalesce(
                                                (
                                                    select
                                                        jsonb_agg(
                                                            jsonb_build_object(
                                                                'oid', pf.oid::int,
                                                                'name', pf.conname::text,
                                                                'local_table_meta', jsonb_build_object(
                                                                    'oid', pf.conrelid::int,
                                                                    'name', pa_local.relname::text,
                                                                    'column_attnums', pf.conkey,
                                                                      'column_names', (
                                                                        select
                                                                            array_agg(pa.attname order by pfck.attnum_ix asc)
                                                                        from
                                                                            unnest(pf.conkey) with ordinality pfck(attnum, attnum_ix)
                                                                            join pg_attribute pa
                                                                                on pfck.attnum = pa.attnum
                                                                        where
                                                                            pa.attrelid = pf.conrelid
                                                                    ),
                                                                    'directives', jsonb_build_object(
                                                                        'inflect_names', schema_directives.inflect_names,
                                                                        'name', graphql.comment_directive(pg_catalog.obj_description(pf.conrelid, 'pg_class')) ->> 'name'
                                                                    )
                                                                ),
                                                                'referenced_table_meta', jsonb_build_object(
                                                                    'oid', pf.confrelid::int,
                                                                    'name', pa_referenced.relname::text,
                                                                    'column_attnums', pf.confkey,
                                                                    'column_names', (
                                                                        select
                                                                            array_agg(pa.attname order by pfck.attnum_ix asc)
                                                                        from
                                                                            unnest(pf.confkey) with ordinality pfck(attnum, attnum_ix)
                                                                            join pg_attribute pa
                                                                                on pfck.attnum = pa.attnum
                                                                        where
                                                                            pa.attrelid = pf.confrelid
                                                                    ),
                                                                    'directives', jsonb_build_object(
                                                                        'inflect_names', schema_directives.inflect_names,
                                                                        'name', graphql.comment_directive(pg_catalog.obj_description(pf.confrelid, 'pg_class')) ->> 'name'
                                                                    )
                                                                ),
                                                                'directives', jsonb_build_object(
                                                                    'inflect_names', schema_directives.inflect_names,
                                                                    'local_name', graphql.comment_directive(pg_catalog.obj_description(pf.oid, 'pg_constraint')) ->> 'local_name',
                                                                    'foreign_name', graphql.comment_directive(pg_catalog.obj_description(pf.oid, 'pg_constraint')) ->> 'foreign_name'
                                                                ),
                                                                'comment', pg_catalog.obj_description(pf.oid, 'pg_constraint'),
                                                                -- If the local fkey columns are unique, the connection type based on
                                                                -- this foregin key should be to-one vs to-many so we check pg_index
                                                                -- to find any unique combinations of keys in the referenced table
                                                                'is_locally_unique', x.is_unique,
                                                                'permissions', jsonb_build_object(
                                                                    -- all columns reference by fkey are selectable
                                                                    'is_selectable', (
                                                                        select
                                                                            bool_and(
                                                                                pg_catalog.has_column_privilege(
                                                                                    current_user,
                                                                                    pa.attrelid,
                                                                                    pa.attname,
                                                                                    'SELECT'
                                                                                )
                                                                            )
                                                                        from
                                                                            pg_attribute pa
                                                                        where
                                                                            (pa.attrelid = pf.conrelid and pa.attnum = any(pf.conkey))
                                                                            or (pa.attrelid = pf.confrelid and pa.attnum = any(pf.confkey))
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    from
                                                        pg_catalog.pg_constraint pf
                                                        join pg_class pa_local
                                                            on pf.conrelid = pa_local.oid
                                                        join pg_class pa_referenced
                                                            on pf.confrelid = pa_referenced.oid
                                                        -- Referenced tables must also be on the search path
                                                        join (
                                                            select
                                                                x.y::regnamespace::oid
                                                            from
                                                                unnest(current_schemas(false)) x(y)
                                                        ) ref_schemas(oid)
                                                            on pa_referenced.relnamespace = ref_schemas.oid,
                                                        lateral (
                                                            select
                                                                exists(
                                                                        select
                                                                            1
                                                                        from
                                                                            pg_index pi
                                                                        where
                                                                            pi.indrelid = pf.conrelid
                                                                            and pi.indkey::int2[] <@ pf.conkey -- are the unique cols in by the fkey cols
                                                                            and pi.indisunique
                                                                            and pi.indisready
                                                                            and pi.indisvalid
                                                                            and pi.indpred is null -- exclude partial indexes
                                                                ) is_unique
                                                        ) x
                                                    where
                                                        pf.contype = 'f' -- foreign key
                                                        and pf.conrelid = pc.oid
                                                ),
                                                jsonb_build_array()
                                            )
                                        ),
                                        'columns', (
                                            select
                                                jsonb_agg(
                                                    jsonb_build_object(
                                                        'name', pa.attname::text,
                                                        'type_oid', pa.atttypid::int,
                                                        'type_name', pa.atttypid::regtype::text,
                                                        'is_not_null', pa.attnotnull,
                                                        'attribute_num', pa.attnum,
                                                        'has_default', pd.adbin is not null, -- pg_get_expr(pd.adbin, pd.adrelid) shows expression
                                                        'is_serial', pg_get_serial_sequence(pc.oid::regclass::text, pa.attname::text) is not null,
                                                        'is_generated', pa.attgenerated <> ''::"char",
                                                        'permissions', jsonb_build_object(
                                                            'is_insertable', pg_catalog.has_column_privilege(
                                                                current_user,
                                                                pa.attrelid,
                                                                pa.attname,
                                                                'INSERT'
                                                            ),
                                                            'is_selectable', pg_catalog.has_column_privilege(
                                                                current_user,
                                                                pa.attrelid,
                                                                pa.attname,
                                                                'SELECT'
                                                            ),
                                                            'is_updatable', pg_catalog.has_column_privilege(
                                                                current_user,
                                                                pa.attrelid,
                                                                pa.attname,
                                                                'UPDATE'
                                                            )
                                                        ),
                                                        'comment', pg_catalog.col_description(pc.oid, pa.attnum),
                                                        'directives', jsonb_build_object(
                                                            'inflect_names', schema_directives.inflect_names,
                                                            'name', graphql.comment_directive(pg_catalog.col_description(pc.oid, pa.attnum)) ->> 'name'
                                                        )
                                                    )
                                                    order by pa.attnum
                                                )
                                            from
                                                pg_catalog.pg_attribute pa
                                                left join pg_catalog.pg_attrdef pd
                                                    on (pa.attrelid, pa.attnum) = (pd.adrelid, pd.adnum)
                                            where
                                                pc.oid = pa.attrelid
                                                and pa.attnum > 0
                                                and not pa.attisdropped
                                        ),
                                        'permissions', jsonb_build_object(
                                            'is_insertable', pg_catalog.has_table_privilege(
                                                current_user,
                                                pc.oid,
                                                'INSERT'
                                            ),
                                            'is_selectable', pg_catalog.has_table_privilege(
                                                current_user,
                                                pc.oid,
                                                'SELECT'
                                            ),
                                            'is_updatable', pg_catalog.has_table_privilege(
                                                current_user,
                                                pc.oid,
                                                'UPDATE'
                                            ),
                                            'is_deletable', pg_catalog.has_table_privilege(
                                                current_user,
                                                pc.oid,
                                                'DELETE'
                                            )
                                        )
                                    )
                                )
                        from
                            pg_class pc
                        where
                            pc.relnamespace = pn.oid
                            and pc.relkind = 'r' -- tables
                        ),
                        jsonb_build_array()
                    )
                )
            ),
            jsonb_build_array()
        )
    )
from
    pg_namespace pn
    -- filter to current schemas only
    join (
        select
            x.y::regnamespace::oid
        from
            unnest(current_schemas(false)) x(y)
    ) cur_schemas(oid)
        on pn.oid = cur_schemas.oid,
    lateral (
        select
            coalesce(
                (graphql.comment_directive(pg_catalog.obj_description(pn.oid, 'pg_namespace')) -> 'inflect_names') = to_jsonb(true),
                false
            ) as inflect_names
    ) schema_directives
where
    pg_catalog.has_schema_privilege(
        current_user,
        pn.oid,
        'USAGE'
    )
