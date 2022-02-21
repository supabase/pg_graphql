create view graphql.type as
    select
        id,
        type_kind,
        meta_kind,
        is_builtin,
        constant_name,
        name,
        entity,
        graphql_type_id,
        enum,
        description
    from
        graphql._type t
        left join pg_class pc
            on t.entity = pc.oid
        left join pg_type tp
            on t.enum = tp.oid
    where
        t.name ~ '^[_A-Za-z][_0-9A-Za-z]*$'
        and (
            t.entity is null
            or (
                case
                    when meta_kind in (
                        'Node',
                        'Edge',
                        'Connection',
                        'OrderBy',
                        'UpdateNodeResponse',
                        'DeleteNodeResponse'
                    )
                        then
                            pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'SELECT'
                            )
                    when meta_kind = 'FilterEntity'
                        then
                            pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'SELECT'
                            ) or pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'UPDATE'
                            ) or pg_catalog.has_table_privilege(
                                current_user,
                                t.entity,
                                'DELETE'
                            )
                    when meta_kind = 'CreateNode'
                        then
                            pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'INSERT'
                            ) and pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'SELECT'
                            )
                    when meta_kind = 'UpdateNode'
                        then
                            pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'UPDATE'
                            ) and pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'SELECT'
                            )
                    else true
                end
                -- ensure regclass' schema is on search_path
                and pc.relnamespace::regnamespace::name = any(current_schemas(false))
            )
        )
        and (
            t.enum is null
            or (
                pg_catalog.has_type_privilege(
                    current_user,
                    t.enum,
                    'USAGE'
                )
                -- ensure enum's schema is on search_path
                and tp.typnamespace::regnamespace::name = any(current_schemas(false))
            )
        );
