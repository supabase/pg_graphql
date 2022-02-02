create view graphql.enum_value as
    select
        type_,
        value,
        column_name,
        description
    from
        (
            select
                type_::text,
                value::text,
                null::text as column_name,
                0 as column_attribute_num,
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
                null::text,
                0,
                null::text
            from
                graphql.type ty
                join pg_enum e
                    on ty.enum = e.enumtypid
            where
                ty.enum is not null
            union all
            select
                gt.name,
                graphql.field_name_for_column(ec.entity, ec.column_name),
                ec.column_name,
                ec.column_attribute_num,
                null::text
            from
                graphql.type gt
                join graphql.entity_column ec
                    on gt.entity = ec.entity
            where
                gt.meta_kind = 'SelectableColumns'
                and pg_catalog.has_column_privilege(
                    current_user,
                    gt.entity,
                    ec.column_name,
                    'SELECT'
                )
            union all
            select
                gt.name,
                graphql.field_name_for_column(ec.entity, ec.column_name),
                ec.column_name,
                ec.column_attribute_num,
                null::text
            from
                graphql.type gt
                join graphql.entity_column ec
                    on gt.entity = ec.entity
            where
                gt.meta_kind = 'UpdatableColumns'
                and not ec.is_generated
                and pg_catalog.has_column_privilege(
                    current_user,
                    gt.entity,
                    ec.column_name,
                    'UPDATE'
                )
        ) x
    order by
        type_,
        column_attribute_num,
        value,
        description;
