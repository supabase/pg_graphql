create view graphql.type as
    with d(dialect) as (
        select
            -- do not inline this call as it has a significant performance impact
            --coalesce(current_setting('graphql.dialect', true), 'default')
            'default'
    )
    select
       graphql.type_name(
            rec := t,
            dialect := d.dialect
       ) as name,
       t.*
    from
        graphql.__type t,
        d
    where
        t.entity is null
        or pg_catalog.has_any_column_privilege(current_user, t.entity, 'SELECT');
