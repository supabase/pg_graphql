create or replace function graphql.rebuild_types()
    returns void
    language plpgsql
    as
$$
begin
    truncate table graphql.__type;

    insert into graphql.__type(type_kind, meta_kind, is_builtin, description)
        select
            type_kind::graphql.type_kind,
            meta_kind::graphql.meta_kind,
            true::bool,
            null::text
        from (
            values
            ('ID',       'SCALAR', true, null),
            ('Int',      'SCALAR', true, null),
            ('Float',    'SCALAR', true, null),
            ('String',   'SCALAR', true, null),
            ('Boolean',  'SCALAR', true, null),
            ('DateTime', 'SCALAR', true, null),
            ('BigInt',   'SCALAR', true, null),
            ('UUID',     'SCALAR', true, null),
            ('JSON',     'SCALAR', true, null),
            ('Cursor',   'SCALAR', false, null),
            ('Query',    'OBJECT', false, null),
            --('Mutation', 'OBJECT', 'MUTATION', null),
            ('PageInfo',  'OBJECT', false, null),
            -- Introspection System
            ('__TypeKind', 'ENUM', true, 'An enum describing what kind of type a given `__Type` is.'),
            ('__Schema', 'OBJECT', true, 'A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.'),
            ('__Type', 'OBJECT', true, 'The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the `__TypeKind` enum.\n\nDepending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional `specifiedByURL`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.'),
            ('__Field', 'OBJECT', true, 'Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.'),
            ('__InputValue', 'OBJECT', true, 'Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.'),
            ('__EnumValue', 'OBJECT', true, 'One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.'),
            ('__DirectiveLocation', 'ENUM', true, 'A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.'),
            ('__Directive', 'OBJECT', true, 'A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.\n\nIn some cases, you need to provide options to alter GraphQL execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.'),
            -- pg_graphql constant
            ('OrderByDirection', 'ENUM', false, 'Defines a per-field sorting order')
       ) x(meta_kind, type_kind, is_builtin, description);


    insert into graphql.__type(type_kind, meta_kind, description, graphql_type)
       values
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Int"',      'Int'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Float"',    'Float'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "String"',   'String'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Boolean"',  'Boolean'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "DateTime"', 'DateTime'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "BigInt"',   'BigInt'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "UUID"',     'UUID'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "JSON"',     'JSON');


    insert into graphql.__type(type_kind, meta_kind, description, entity)
        select
           x.*
        from
            graphql.entity ent,
            lateral (
                values
                    ('OBJECT'::graphql.type_kind, 'Node'::graphql.meta_kind, null::text, ent.entity),
                    ('OBJECT',                    'Edge',                     null,       ent.entity),
                    ('OBJECT',                    'Connection',               null,       ent.entity),
                    ('INPUT_OBJECT',              'OrderBy',                  null,       ent.entity),
                    ('INPUT_OBJECT',              'FilterEntity',             null,       ent.entity)
            ) x(type_kind, meta_kind, description, entity);


    insert into graphql.__type(type_kind, meta_kind, description, enum)
        select
           'ENUM', 'Enum', null, t.oid::regtype
        from
            pg_type t
        where
            t.typnamespace not in (
                'information_schema'::regnamespace,
                'pg_catalog'::regnamespace,
                'graphql'::regnamespace
            )
            and exists (select 1 from pg_enum e where e.enumtypid = t.oid);
end;
$$;
