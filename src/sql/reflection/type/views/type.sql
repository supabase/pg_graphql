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
    where
        t.entity is null
        or pg_catalog.has_any_column_privilege(
            current_user,
            t.entity,
            'SELECT'
        );
