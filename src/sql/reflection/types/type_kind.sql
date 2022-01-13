-- https://github.com/graphql/graphql-js/blob/main/src/type/introspection.ts#L197
create type graphql.type_kind as enum (
    'SCALAR',
    'OBJECT',
    'INTERFACE',
    'UNION',
    'ENUM',
    'INPUT_OBJECT',
    'LIST',
    'NON_NULL'
);
