create type graphql.meta_kind as enum (
    'NODE', 'EDGE', 'CONNECTION', 'CUSTOM_SCALAR', 'PAGE_INFO',
    'CURSOR', 'QUERY', 'MUTATION', 'BUILTIN', 'INTERFACE',
    -- Introspection types
    '__SCHEMA', '__TYPE', '__TYPE_KIND', '__FIELD', '__INPUT_VALUE', '__ENUM_VALUE', '__DIRECTIVE', '__DIRECTIVE_LOCATION',
    -- Custom
    'ORDER_BY_DIRECTION', 'ORDER_BY', 'FILTER_FIELD', 'FILTER_ENTITY'
);
