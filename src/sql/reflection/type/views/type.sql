create view graphql.type as
    select
       t.*
    from
        graphql._type t
    where
        t.entity is null
        or pg_catalog.has_any_column_privilege(current_user, t.entity, 'SELECT');
