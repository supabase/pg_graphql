create view graphql.enum_value as
    select
        type_::text,
        value::text,
        description::text
    from (
        values
            ('__TypeKind', 'SCALAR', null::text),
            ('__TypeKind', 'OBJECT', null),
            ('__TypeKind', 'INTERFACE', null),
            ('__TypeKind', 'UNION', null),
            ('__TypeKind', 'ENUM', null),
            ('__TypeKind', 'INPUT_OBJECT', null),
            ('__TypeKind', 'LIST', null),
            ('__TypeKind', 'NON_NULL', null),
            ('__DirectiveLocation', 'QUERY', 'Location adjacent to a query operation.'),
            ('__DirectiveLocation', 'MUTATION', 'Location adjacent to a mutation operation.'),
            ('__DirectiveLocation', 'SUBSCRIPTION', 'Location adjacent to a subscription operation.'),
            ('__DirectiveLocation', 'FIELD', 'Location adjacent to a field.'),
            ('__DirectiveLocation', 'FRAGMENT_DEFINITION', 'Location adjacent to a fragment definition.'),
            ('__DirectiveLocation', 'FRAGMENT_SPREAD', 'Location adjacent to a fragment spread.'),
            ('__DirectiveLocation', 'INLINE_FRAGMENT', 'Location adjacent to an inline fragment.'),
            ('__DirectiveLocation', 'VARIABLE_DEFINITION', 'Location adjacent to a variable definition.'),
            ('__DirectiveLocation', 'SCHEMA', 'Location adjacent to a schema definition.'),
            ('__DirectiveLocation', 'SCALAR', 'Location adjacent to a scalar definition.'),
            ('__DirectiveLocation', 'OBJECT', 'Location adjacent to an object type definition.'),
            ('__DirectiveLocation', 'FIELD_DEFINITION', 'Location adjacent to a field definition.'),
            ('__DirectiveLocation', 'ARGUMENT_DEFINITION', 'Location adjacent to an argument definition.'),
            ('__DirectiveLocation', 'INTERFACE', 'Location adjacent to an interface definition.'),
            ('__DirectiveLocation', 'UNION', 'Location adjacent to a union definition.'),
            ('__DirectiveLocation', 'ENUM', 'Location adjacent to an enum definition.'),
            ('__DirectiveLocation', 'ENUM_VALUE', 'Location adjacent to an enum value definition.'),
            ('__DirectiveLocation', 'INPUT_OBJECT', 'Location adjacent to an input object type definition.'),
            ('__DirectiveLocation', 'INPUT_FIELD_DEFINITION', 'Location adjacent to an input object field definition.'),
            -- pg_graphql Constant
            ('OrderByDirection', 'AscNullsFirst', 'Ascending order, nulls first'),
            ('OrderByDirection', 'AscNullsLast', 'Ascending order, nulls last'),
            ('OrderByDirection', 'DescNullsFirst', 'Descending order, nulls first'),
            ('OrderByDirection', 'DescNullsLast', 'Descending order, nulls last')
    ) x(type_, value, description)
    union all
    select
        ty.name,
        e.enumlabel as value,
        null::text
    from
        graphql.type ty
        join pg_enum e
            on ty.enum = e.enumtypid
    where
        ty.enum is not null;
