create table graphql.__type (
    id serial primary key,
    type_kind graphql.type_kind not null,
    meta_kind graphql.meta_kind not null,
    is_builtin bool not null default false,
    entity regclass,
    graphql_type text,
    enum regtype,
    description text,
    unique (meta_kind, entity),
    check (entity is null or graphql_type is null)
);
