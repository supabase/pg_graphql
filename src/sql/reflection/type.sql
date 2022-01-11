create materialized view graphql._type (
    name,
    type_kind,
    meta_kind,
    description,
    entity
) as
    select
        name,
        type_kind::graphql.type_kind,
        meta_kind::graphql.meta_kind,
        description,
        null::regclass as entity
    from (
        values
        ('ID', 'SCALAR', 'BUILTIN', null),
        ('Int', 'SCALAR', 'BUILTIN', null),
        ('Float', 'SCALAR', 'BUILTIN', null),
        ('String', 'SCALAR', 'BUILTIN', null),
        ('Boolean', 'SCALAR', 'BUILTIN', null),
        ('DateTime', 'SCALAR', 'CUSTOM_SCALAR', null),
        ('BigInt', 'SCALAR', 'CUSTOM_SCALAR', null),
        ('UUID', 'SCALAR', 'CUSTOM_SCALAR', null),
        ('JSON', 'SCALAR', 'CUSTOM_SCALAR', null),
        ('Cursor', 'SCALAR', 'CUSTOM_SCALAR', null),
        ('Query', 'OBJECT', 'QUERY', null),
        --('Mutation', 'OBJECT', 'MUTATION', null),
        ('PageInfo', 'OBJECT', 'PAGE_INFO', null),
        -- Introspection System
        ('__TypeKind', 'ENUM', '__TYPE_KIND', 'An enum describing what kind of type a given `__Type` is.'),
        ('__Schema', 'OBJECT', '__SCHEMA', 'A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.'),
        ('__Type', 'OBJECT', '__TYPE', 'The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the `__TypeKind` enum.\n\nDepending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional `specifiedByURL`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.'),
        ('__Field', 'OBJECT', '__FIELD', 'Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.'),
        ('__InputValue', 'OBJECT', '__INPUT_VALUE', 'Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.'),
        ('__EnumValue', 'OBJECT', '__ENUM_VALUE', 'One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.'),
        ('__DirectiveLocation', 'ENUM', '__DIRECTIVE_LOCATION', 'A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.'),
        ('__Directive', 'OBJECT', '__DIRECTIVE', 'A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.\n\nIn some cases, you need to provide options to alter GraphQL execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.'),
        -- pg_graphql constant
        ('OrderByDirection', 'ENUM', 'ORDER_BY_DIRECTION', 'Defines a per-field sorting order'),
        -- Type filters
        ('IntFilter', 'INPUT_OBJECT', 'FILTER_FIELD', 'Boolean expression comparing fields on type "Int"'),
        ('FloatFilter', 'INPUT_OBJECT', 'FILTER_FIELD', 'Boolean expression comparing fields on type "Float"'),
        ('StringFilter', 'INPUT_OBJECT', 'FILTER_FIELD', 'Boolean expression comparing fields on type "String"'),
        ('BooleanFilter', 'INPUT_OBJECT', 'FILTER_FIELD', 'Boolean expression comparing fields on type "Boolean"'),
        ('DateTimeFilter', 'INPUT_OBJECT', 'FILTER_FIELD', 'Boolean expression comparing fields on type "DateTime"'),
        ('BigIntFilter', 'INPUT_OBJECT', 'FILTER_FIELD', 'Boolean expression comparing fields on type "BigInt"'),
        ('UUIDFilter', 'INPUT_OBJECT', 'FILTER_FIELD', 'Boolean expression comparing fields on type "UUID"'),
        ('JSONFilter', 'INPUT_OBJECT', 'FILTER_FIELD', 'Boolean expression comparing fields on type "JSON"')
    ) as const(name, type_kind, meta_kind, description)
    union all
    select
        x.*
    from
        graphql.entity ent,
        lateral (
            select
                graphql.to_pascal_case(graphql.to_table_name(ent.entity)) table_name_pascal_case
        ) names_,
        lateral (
            values
                (names_.table_name_pascal_case::text, 'OBJECT'::graphql.type_kind, 'NODE'::graphql.meta_kind, null::text, ent.entity),
                (names_.table_name_pascal_case || 'Edge', 'OBJECT', 'EDGE', null, ent.entity),
                (names_.table_name_pascal_case || 'Connection', 'OBJECT', 'CONNECTION', null, ent.entity),
                (names_.table_name_pascal_case || 'OrderBy', 'INPUT_OBJECT', 'ORDER_BY', null, ent.entity),
                (names_.table_name_pascal_case || 'Filter', 'INPUT_OBJECT', 'FILTER_ENTITY', null, ent.entity)
        ) x
    union all
    select
        graphql.to_pascal_case(t.typname), 'ENUM', 'CUSTOM_SCALAR', null, null
    from
        pg_type t
    where
        t.typnamespace not in ('information_schema'::regnamespace, 'pg_catalog'::regnamespace, 'graphql'::regnamespace)
        and exists (select 1 from pg_enum e where e.enumtypid = t.oid);


create view graphql.type as
    select
        -- todo: type name transform rules
        case
            when t.meta_kind = 'BUILTIN' then t.name
            else t.name
        end as name,
        t.type_kind,
        t.meta_kind,
        t.description,
        t.entity
    from
        graphql._type t
    where
        t.entity is null
        or pg_catalog.has_any_column_privilege(current_user, t.entity, 'SELECT');
