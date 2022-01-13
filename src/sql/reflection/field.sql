create materialized view graphql._field_output as
    select
        parent_type,
        type_,
        name,
        -- internal flags
        is_not_null,
        is_array,
        is_array_not_null,
        false is_arg,
        null::text as parent_arg_field_name, -- if is_arg, parent_arg_field_name is required
        null::text as default_value,
        description,
        null::text as column_name,
        null::regtype as column_type,
        null::text[] parent_columns,
        null::text[] local_columns,
        case
            when name in ('__type', '__schema') then true
            else false
        end as is_hidden_from_schema
    from (
        values
            ('__Schema', 'String', 'description', false, false, null, null),
            ('__Schema', '__Type', 'types', true, true, true, 'A list of all types supported by this server.'),
            ('__Schema', '__Type', 'queryType', true, false, null, 'The type that query operations will be rooted at.'),
            ('__Schema', '__Type', 'mutationType', false, false, null, 'If this server supports mutation, the type that mutation operations will be rooted at.'),
            ('__Schema', '__Type', 'subscriptionType', false, false, null, 'If this server support subscription, the type that subscription operations will be rooted at.'),
            ('__Schema', '__Directive', 'directives', true, true, true, 'A list of all directives supported by this server.'),
            ('__Directive', 'String', 'name', true, false, null, null),
            ('__Directive', 'String', 'description', false, false, null, null),
            ('__Directive', 'Boolean', 'isRepeatable', true, false, null, null),
            ('__Directive', '__DirectiveLocation', 'locations', true, true, true, null),
            ('__Directive', '__InputValue', 'args', true, true, true, null),
            ('__Type', '__TypeKind', 'kind', true, false, null, null),
            ('__Type', 'String', 'name', false, false, null, null),
            ('__Type', 'String', 'description', false, false, null, null),
            ('__Type', 'String', 'specifiedByURL', false, false, null, null),
            ('__Type', '__Field', 'fields', false, true, true, null),
            ('__Type', '__Type', 'interfaces', true, true, false, null),
            ('__Type', '__Type', 'possibleTypes', true, true, false, null),
            ('__Type', '__EnumValue', 'enumValues', true, true, false, null),
            ('__Type', '__InputValue', 'inputFields', true, true, false, null),
            ('__Type', '__Type', 'ofType', false, false, null, null),
            ('__Field', 'Boolean', 'isDeprecated', true, false, null, null),
            ('__Field', 'String', 'deprecationReason', false, false, null, null),
            ('__Field', '__InputValue', 'args', true, true, true, null),
            ('__Field', '__Type', 'type', true, false, null, null),
            ('__InputValue', 'String', 'name', true, false, null, null),
            ('__InputValue', 'String', 'description', false, false, null, null),
            ('__InputValue', 'String', 'defaultValue', false, false, null, 'A GraphQL-formatted string representing the default value for this input value.'),
            ('__InputValue', 'Boolean', 'isDeprecated', true, false, null, null),
            ('__InputValue', 'String', 'deprecationReason', false, false, null, null),
            ('__InputValue', '__Type', 'type', true, false, null, null),
            ('__EnumValue', 'String', 'name', true, false, null, null),
            ('__EnumValue', 'String', 'description', false, false, null, null),
            ('__EnumValue', 'Boolean', 'isDeprecated', true, false, null, null),
            ('__EnumValue', 'String', 'deprecationReason', false, false, null, null),
            ('PageInfo', 'Boolean', 'hasPreviousPage', true, false, null, null),
            ('PageInfo', 'Boolean', 'hasNextPage', true, false, null, null),
            ('PageInfo', 'String', 'startCursor', true, false, null, null),
            ('PageInfo', 'String', 'endCursor', true, false, null, null),
            ('Query', '__Type', '__type', true, false, null, null), -- todo is_hidden_from_schema = true
            ('Query', '__Schema', '__schema', true, false, null, null) -- todo is_hidden_from_schema = true
        ) x(parent_type, type_, name, is_not_null, is_array, is_array_not_null, description)
        union all
        select
            fs.parent_type,
            fs.type_,
            fs.name,
            fs.is_not_null,
            fs.is_array,
            fs.is_array_not_null,
            false as is_arg,
            null::text as parent_arg_field_name,
            null::text as default_value,
            fs.description,
            fs.column_name,
            null::regtype as column_type,
            fs.parent_columns,
            fs.local_columns,
            fs.is_hidden_from_schema
        from
            graphql.type conn
            join graphql.type edge
                on conn.entity = edge.entity
            join graphql.type node
                on edge.entity = node.entity,
            lateral (
                values
                    (node.name, 'String', '__typename', true, false, null, null, null, null, null, true),
                    (edge.name, 'String', '__typename', true, false, null, null, null, null, null, true),
                    (conn.name, 'String', '__typename', true, false, null, null, null, null, null, true),
                    (edge.name, node.name, 'node', false, false, null::boolean, null::text, null::text, null::text[], null::text[], false),
                    (edge.name, 'String', 'cursor', true, false, null, null, null, null, null, false),
                    (conn.name, edge.name, 'edges', true, true, true, null, null, null, null, false),
                    (conn.name, 'PageInfo', 'pageInfo', true, false, null, null, null, null, null, false),
                    (conn.name, 'Int', 'totalCount', true, false, null, null, null, null, null, false),
                    (node.name, 'ID', 'nodeId', true, false, null, null, null, null, null, false),
                    ('Query', node.name, graphql.to_camel_case(graphql.to_table_name(node.entity)), false, false, null, null, null, null, null, false),
                    ('Query', conn.name, graphql.to_camel_case('all_' || graphql.to_table_name(conn.entity) || 's'), false, false, null, null, null, null, null, false)
            ) fs(parent_type, type_, name, is_not_null, is_array, is_array_not_null, description, column_name, parent_columns, local_columns, is_hidden_from_schema)
        where
            conn.meta_kind = 'Connection'
            and edge.meta_kind = 'Edge'
            and node.meta_kind = 'Node'
        -- Node
        -- Node.<column>
        union all
        select
            gt.name parent_type,
            -- substring removes the underscore prefix from array types
            graphql.sql_type_to_graphql_type(regexp_replace(tf.type_str, '\[\]$', '')) as type_,
            graphql.to_camel_case(pa.attname::text) as name,
            pa.attnotnull as is_not_null,
            tf.type_str like '%[]' as is_array,
            pa.attnotnull and tf.type_str like '%[]' as is_array_not_null,
            false as is_arg,
            null::text as parent_arg_field_name,
            null::text as default_value,
            null::text description,
            pa.attname::text as column_name,
            pa.atttypid::regtype as column_type,
            null::text[],
            null::text[],
            false
        from
            graphql.type gt
            join pg_attribute pa
                on gt.entity = pa.attrelid,
            lateral (
                select pg_catalog.format_type(atttypid, atttypmod) type_str
            ) tf
        where
            gt.meta_kind = 'Node'
            and pa.attnum > 0
            and not pa.attisdropped
        union all
        -- Node.<relationship>
        -- Node.<connection>
        select
            node.name parent_type,
            conn.name type_,
            case
                when (
                    conn.meta_kind = 'Connection'
                    and rel.foreign_cardinality = 'MANY'
                ) then graphql.to_camel_case(graphql.to_table_name(rel.foreign_entity)) || 's'

                -- owner_id -> owner
                when (
                    conn.meta_kind = 'Node'
                    and rel.foreign_cardinality = 'ONE'
                    and array_length(rel.local_columns, 1) = 1
                    and rel.local_columns[1] like '%_id'
                ) then graphql.to_camel_case(left(rel.local_columns[1], -3))

                when rel.foreign_cardinality = 'ONE' then graphql.to_camel_case(graphql.to_table_name(rel.foreign_entity))

                else graphql.to_camel_case(graphql.to_table_name(rel.foreign_entity)) || 'RequiresNameOverride'
            end,
            false as is_not_null, -- todo: reference column nullability
            false as is_array,
            null as is_array_not_null,
            false as is_arg,
            null::text as parent_arg_field_name,
            null::text as default_value,
            null description,
            null column_name,
            null::regtype as column_type,
            rel.local_columns,
            rel.foreign_columns,
            false
        from
            graphql.type node
            join graphql.relationship rel
                on node.entity = rel.local_entity
            join graphql.type conn
                on conn.entity = rel.foreign_entity
                and (
                    (conn.meta_kind = 'Node' and rel.foreign_cardinality = 'ONE')
                    or (conn.meta_kind = 'Connection' and rel.foreign_cardinality = 'MANY')
                )
        where
            node.meta_kind = 'Node'
        -- NodeOrderBy
        union all
        select
            gt.name parent_type,
            'OrderByDirection' as type_,
            graphql.to_camel_case(pa.attname::text) as name,
            false is_not_null,
            false is_array,
            null is_array_not_null,
            false as is_arg,
            null::text as parent_arg_field_name,
            null::text as default_value,
            null::text description,
            pa.attname::text as column_name,
            null::regtype as column_type,
            null::text[],
            null::text[],
            false
        from
            graphql.type gt
            join pg_attribute pa
                on gt.entity = pa.attrelid
        where
            gt.meta_kind = 'OrderBy'
            and pa.attnum > 0
            and not pa.attisdropped

        -- <Type>Filter.eq
        union all
        select distinct
            graphql.sql_type_to_graphql_type(regexp_replace(pg_catalog.format_type(pa.atttypid, pa.atttypmod), '\[\]$', '')) || 'Filter' as parent_type,
            graphql.sql_type_to_graphql_type(regexp_replace(pg_catalog.format_type(pa.atttypid, pa.atttypmod), '\[\]$', '')) type_,
            'eq' as name,
            false,
            false,
            null::bool,
            false,
            null::text,
            null::text,
            null::text,
            null::text,
            null::regtype as column_type,
            null::text[],
            null::text[],
            false
        from
            graphql.type gt
            join pg_attribute pa
                on gt.entity = pa.attrelid
        where
            gt.meta_kind = 'FilterEntity'
            and pa.attnum > 0
            and not pa.attisdropped
        -- EntityFilter(column eq)
        union all
        select distinct
            gt.name parent_type,
            graphql.sql_type_to_graphql_type(regexp_replace(pg_catalog.format_type(pa.atttypid, pa.atttypmod), '\[\]$', '')) || 'Filter' as type_,
            graphql.to_camel_case(pa.attname::text) as name,
            false is_not_null,
            false is_array,
            null::bool is_array_not_null,
            false as is_arg,
            null::text as parent_arg_field_name,
            null::text as default_value,
            null::text description,
            pa.attname::text as column_name,
            null::regtype as column_type,
            null::text[],
            null::text[],
            false
        from
            graphql.type gt
            join pg_attribute pa
                on gt.entity = pa.attrelid
        where
            gt.meta_kind = 'FilterEntity'
            and pa.attnum > 0
            and not pa.attisdropped;

create materialized view graphql._field_arg as
    -- Arguments
    -- __Field(includeDeprecated)
    -- __enumValue(includeDeprecated)
    -- __InputFields(includeDeprecated)
    select
        f.type_ as parent_type,
        'Boolean' as type_,
        'includeDeprecated' as name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.name as parent_arg_field_name,
        'f' as default_value,
        null as description,
        null as column_name,
        null::regtype as column_type,
        null::text[] as parent_columns,
        null::text[] as local_columns,
        false as is_hidden_from_schema
    from
        graphql._field_output f
    where
        f.type_ in ('__Field', '__enumValue', '__InputFields')
    union all
    -- __type(name)
    select
        f.type_ as parent_type,
        'String' type_,
        'name' as name,
        true as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.name parent_arg_field_name,
        null as default_value,
        null as description,
        null as column_name,
        null::regtype as column_type,
        null as parent_columns,
        null as local_columns,
        false as is_hidden_from_schema
    from
        graphql._field_output f
    where
        f.name = '__type'
    union all
    -- Node(nodeId)
    select
        f.type_,
        'ID' type_,
        'nodeId' as name,
        true as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.name parent_arg_field_name,
        null as default_value,
        null as description,
        null as column_name,
        null::regtype as column_type,
        null as parent_columns,
        null as local_columns,
        false as is_hidden_from_schema
    from
        graphql.type t
        inner join graphql._field_output f
            on t.name = f.type_
    where
        t.meta_kind = 'Node'
        and f.parent_type = 'Query'
    union all
    -- Connection(first, last)
    select
        f.type_,
        'Int' type_,
        y.name_ as name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.name parent_arg_field_name,
        null as default_value,
        null as description,
        null as column_name,
        null::regtype as column_type,
        null as parent_columns,
        null as local_columns,
        false as is_hidden_from_schema
    from
        graphql.type t
        inner join graphql._field_output f
            on t.name = f.type_,
        lateral (select name_ from unnest(array['first', 'last']) x(name_)) y(name_)
    where
        t.meta_kind = 'Connection'
    -- Connection(before, after)
    union all
    select
        f.type_,
        'Cursor' type_,
        y.name_ as name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.name parent_arg_field_name,
        null as default_value,
        null as description,
        null as column_name,
        null::regtype as column_type,
        null as parent_columns,
        null as local_columns,
        false as is_hidden_from_schema
    from
        graphql.type t
        inner join graphql._field_output f
            on t.name = f.type_,
        lateral (select name_ from unnest(array['before', 'after']) x(name_)) y(name_)
    where
        t.meta_kind = 'Connection'
    -- Connection(orderBy)
    union all
    select
        f.type_,
        tt.name type_,
        'orderBy' as name,
        true as is_not_null,
        true as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.name parent_arg_field_name,
        null as default_value,
        null as description,
        null as column_name,
        null::regtype as column_type,
        null as parent_columns,
        null as local_columns,
        false as is_hidden_from_schema
    from
        graphql.type t
        inner join graphql._field_output f
            on t.name = f.type_
            and t.meta_kind = 'Connection'
        inner join graphql.type tt
            on t.entity = tt.entity
            and tt.meta_kind = 'OrderBy'
    -- Connection(filter)
    union all
    select
        f.type_,
        tt.name type_,
        'filter' as name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.name parent_arg_field_name,
        null as default_value,
        null as description,
        null as column_name,
        null::regtype as column_type,
        null as parent_columns,
        null as local_columns,
        false as is_hidden_from_schema
    from
        graphql.type t
        inner join graphql._field_output f
            on t.name = f.type_
            and t.meta_kind = 'Connection'
        inner join graphql.type tt
            on t.entity = tt.entity
            and tt.meta_kind = 'FilterEntity';

create view graphql.field as
    select
        f.parent_type,
        f.type_,
        f.name, -- todo: apply overrides
        f.is_not_null,
        f.is_array,
        f.is_array_not_null,
        f.is_arg,
        f.parent_arg_field_name,
        f.default_value,
        f.description,
        f.column_name,
        f.column_type,
        f.parent_columns,
        f.local_columns,
        f.is_hidden_from_schema
    from
        (
            select * from graphql._field_output
            union all
            select * from graphql._field_arg
        ) f
        join graphql.type t
            on f.parent_type = t.name
    where
        -- Apply visibility rules
        case
            when f.name = 'nodeId' then true
            when t.entity is null then true
            when f.column_name is null then true
            when (
                f.column_name is not null
                and pg_catalog.has_column_privilege(current_user, t.entity, f.column_name, 'SELECT')
            ) then true
            -- TODO: check if relationships are accessible
            when f.local_columns is not null then true
            else false
        end;
