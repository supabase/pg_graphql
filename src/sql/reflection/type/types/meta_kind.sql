create type graphql.meta_kind as enum (
-- Constant

    -- Introspection types
    '__Schema',
    '__Type',
    '__TypeKind',
    '__Field',
    '__InputValue',
    '__EnumValue',
    '__Directive',
    '__DirectiveLocation',

    -- Builtin Scalar
    'ID',
    'Float',
    'String',
    'Int',
    'Boolean',
    'DateTime',
    'BigInt',
    'UUID',
    'JSON',

    -- Custom Scalar
    'OrderByDirection',
    'PageInfo',
    'Cursor',

    'Query',
    'Mutation',

-- Multi-possible
    'Interface',

-- Entity derrived
    'Node',
    'Edge',
    'Connection',
    'OrderBy',
    'FilterEntity',
    'CreateNode',
    'UpdateNode',
    'UpdateNodeResponse',
    'DeleteNodeResponse',

-- GraphQL Type Derived
    'FilterType',

-- Enum Derived
    'Enum'
);
