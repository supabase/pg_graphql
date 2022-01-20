create type graphql.field_meta_kind as enum (
    'PageInfo.hasNextPage',
    'PageInfo.hasPreviousPage',
    'PageInfo.startCursor',
    'PageInfo.endCursor'
);

create table graphql._field (
    id serial primary key,
    parent_type_id int references graphql._type(id),
    type_id  int not null references graphql._type(id),
    constant_name text,
    -- internal flags
    is_not_null boolean not null,
    is_array boolean not null,
    is_array_not_null boolean,
    is_arg boolean default false,
    is_hidden_from_schema boolean default false,
    -- TODO: this is a problem
    parent_arg_field_id int references graphql._field(id), -- if is_arg, parent_arg_field_name is required
    default_value text,
    description text,
    column_name text,
    column_type regtype,

    -- relationships
    parent_columns text[],
    local_columns text[],

    -- identifiers
    meta_kind graphql.field_meta_kind
);


create or replace function graphql.type_id(type_name text)
    returns int
    stable
    language sql
as $$
    select id from graphql.type where name = $1;
$$;


create or replace function graphql.type_id(graphql.meta_kind)
    returns int
    stable
    language sql
as $$
    -- WARNING: meta_kinds are not always unique. Make sure
    -- to only use this function with unique ones
    select id from graphql.type where meta_kind = $1;
$$;



create function graphql.rebuild_fields()
    returns void
    volatile
    language plpgsql
as $$
begin
    truncate table graphql._field cascade;
    alter sequence graphql._field_id_seq restart with 1;

    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_hidden_from_schema, description)
    values
        (graphql.type_id('__Schema'),     graphql.type_id('String'),              'description',       false, false, null, false,  null),
        (graphql.type_id('__Schema'),     graphql.type_id('__Type'),              'types',             true,  true,  true, false,  'A list of all types supported by this server.'),
        (graphql.type_id('__Schema'),     graphql.type_id('__Type'),              'queryType',         true,  false, null, false,  'The type that query operations will be rooted at.'),
        (graphql.type_id('__Schema'),     graphql.type_id('__Type'),              'mutationType',      false, false, null, false,  'If this server supports mutation, the type that mutation operations will be rooted at.'),
        (graphql.type_id('__Schema'),     graphql.type_id('__Type'),              'subscriptionType',  false, false, null, false,  'If this server support subscription, the type that subscription operations will be rooted at.'),
        (graphql.type_id('__Schema'),     graphql.type_id('__Directive'),         'directives',        true,  true,  true, false,  'A list of all directives supported by this server.'),
        (graphql.type_id('__Directive'),  graphql.type_id('String'),              'name',              true,  false, null, false,  null),
        (graphql.type_id('__Directive'),  graphql.type_id('String'),              'description',       false, false, null, false,  null),
        (graphql.type_id('__Directive'),  graphql.type_id('Boolean'),             'isRepeatable',      true,  false, null, false,  null),
        (graphql.type_id('__Directive'),  graphql.type_id('__DirectiveLocation'), 'locations',         true,  true,  true, false,  null),
        (graphql.type_id('__Directive'),  graphql.type_id('__InputValue'),        'args',              true,  true,  true, false,  null),
        (graphql.type_id('__Type'),       graphql.type_id('__TypeKind'),          'kind',              true,  false, null, false,  null),
        (graphql.type_id('__Type'),       graphql.type_id('String'),              'name',              false, false, null, false,  null),
        (graphql.type_id('__Type'),       graphql.type_id('String'),              'description',       false, false, null, false,  null),
        (graphql.type_id('__Type'),       graphql.type_id('String'),              'specifiedByURL',    false, false, null, false,  null),
        (graphql.type_id('__Type'),       graphql.type_id('__Field'),             'fields',            false, true,  true, false,  null),
        (graphql.type_id('__Type'),       graphql.type_id('__Type'),              'interfaces',        true,  true,  false, false, null),
        (graphql.type_id('__Type'),       graphql.type_id('__Type'),              'possibleTypes',     true,  true,  false, false, null),
        (graphql.type_id('__Type'),       graphql.type_id('__EnumValue'),         'enumValues',        true,  true,  false, false, null),
        (graphql.type_id('__Type'),       graphql.type_id('__InputValue'),        'inputFields',       true,  true,  false, false, null),
        (graphql.type_id('__Type'),       graphql.type_id('__Type'),              'ofType',            false, false, null, false,  null),
        (graphql.type_id('__Field'),      graphql.type_id('Boolean'),             'isDeprecated',      true,  false, null, false,  null),
        (graphql.type_id('__Field'),      graphql.type_id('String'),              'deprecationReason', false, false, null, false,  null),
        (graphql.type_id('__Field'),      graphql.type_id('__InputValue'),        'args',              true,  true,  true, false,  null),
        (graphql.type_id('__Field'),      graphql.type_id('__Type'),              'type',              true,  false, null, false,  null),
        (graphql.type_id('__InputValue'), graphql.type_id('String'),              'name',              true,  false, null, false,  null),
        (graphql.type_id('__InputValue'), graphql.type_id('String'),              'description',       false, false, null, false,  null),
        (graphql.type_id('__InputValue'), graphql.type_id('String'),              'defaultValue',      false, false, null, false,  'A GraphQL-formatted string representing the default value for this input value.'),
        (graphql.type_id('__InputValue'), graphql.type_id('Boolean'),             'isDeprecated',      true,  false, null, false,  null),
        (graphql.type_id('__InputValue'), graphql.type_id('String'),              'deprecationReason', false, false, null, false,  null),
        (graphql.type_id('__InputValue'), graphql.type_id('__Type'),              'type',              true,  false, null, false,  null),
        (graphql.type_id('__EnumValue'),  graphql.type_id('String'),              'name',              true,  false, null, false,  null),
        (graphql.type_id('__EnumValue'),  graphql.type_id('String'),              'description',       false, false, null, false,  null),
        (graphql.type_id('__EnumValue'),  graphql.type_id('Boolean'),             'isDeprecated',      true,  false, null, false,  null),
        (graphql.type_id('__EnumValue'),  graphql.type_id('String'),              'deprecationReason', false, false, null, false,  null);


    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_hidden_from_schema, description)
    select
        t.id,
        x.*
    from
        graphql.type t,
        lateral (
            values
                (graphql.type_id('__Type'),   '__type',   true,  false, null::boolean, true,  null::text),
                (graphql.type_id('__Schema'), '__schema', true , false, null,          true,  null)
        ) x(type_id, constant_name, is_not_null, is_array, is_array_not_null, is_hidden_from_schema, description)
    where
        t.meta_kind = 'Query';


    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_hidden_from_schema, description)
    select
        t.id,
        x.*
    from
        graphql.type t,
        lateral (
            values
                (graphql.type_id('__Type'),   '__type',   true,  false, null::boolean, true,  null::text),
                (graphql.type_id('__Schema'), '__schema', true , false, null,          true,  null)
        ) x(type_id, constant_name, is_not_null, is_array, is_array_not_null, is_hidden_from_schema, description)
    where
        t.meta_kind = 'Query';


    insert into graphql._field(parent_type_id, type_id, meta_kind, is_not_null, is_array, is_array_not_null, is_hidden_from_schema, description)
    values
        -- TODO parent type lookup from metakind
        (graphql.type_id('PageInfo'::graphql.meta_kind), graphql.type_id('Boolean'), 'PageInfo.hasPreviousPage', true, false, null, false, null),
        (graphql.type_id('PageInfo'::graphql.meta_kind), graphql.type_id('Boolean'), 'PageInfo.hasNextPage',     true, false, null, false, null),
        (graphql.type_id('PageInfo'::graphql.meta_kind), graphql.type_id('String'),  'PageInfo.startCursor',     true, false, null, false, null),
        (graphql.type_id('PageInfo'::graphql.meta_kind), graphql.type_id('String'),  'PageInfo.endCursor',       true, false, null, false, null);


    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, description, is_hidden_from_schema)

        select
            fs.parent_type_id,
            fs.type_id,
            fs.constant_name,
            fs.is_not_null,
            fs.is_array,
            fs.is_array_not_null,
            fs.description,
            fs.is_hidden_from_schema
        from
            graphql.type conn
            join graphql.type edge
                on conn.entity = edge.entity
            join graphql.type node
                on edge.entity = node.entity,
            lateral (
                values
                    -- TODO replace constant names
                    (node.id, graphql.type_id('String'),   '__typename', true,  false, null, null, null, null, null, true),
                    (edge.id, graphql.type_id('String'),   '__typename', true,  false, null, null, null, null, null, true),
                    (conn.id, graphql.type_id('String'),   '__typename', true,  false, null, null, null, null, null, true),
                    (edge.id, node.id,                      'node',       false, false, null::boolean, null::text, null::text, null::text[], null::text[], false),
                    (edge.id, graphql.type_id('String'),   'cursor',     true,  false, null, null, null, null, null, false),
                    (conn.id, edge.id,                     'edges',      true,  true,  true, null, null, null, null, false),
                    (conn.id, graphql.type_id('Int'),      'totalCount', true,  false, null, null, null, null, null, false),
                    (node.id, graphql.type_id('ID'),       'nodeId',     true,  false, null, null, null, null, null, false),
                    (conn.id, graphql.type_id('PageInfo'::graphql.meta_kind), 'pageInfo',   true,  false, null, null, null, null, null, false),
                    (graphql.type_id('Query'::graphql.meta_kind), node.id,    graphql.to_camel_case(graphql.to_table_name(node.entity)), false, false, null, null, null, null, null, false),
                    (graphql.type_id('Query'::graphql.meta_kind), conn.id,       graphql.to_camel_case('all_' || graphql.to_table_name(conn.entity) || 's'), false, false, null, null, null, null, null, false)
            ) fs(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, description, column_name, parent_columns, local_columns, is_hidden_from_schema)
        where
            conn.meta_kind = 'Connection'
            and edge.meta_kind = 'Edge'
            and node.meta_kind = 'Node';

end;
$$;




/*

insert into graphql._field(parent_type, type_, constnat_name, is_not_null, is_array, is_array_not_null, description, is_hidden_from_schema)
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

*/

create or replace function graphql.field_name(rec graphql._field, dialect text = 'default')
    returns text
    language sql
    stable
as $$
    -- TODO
    select
        case
            when rec.constant_name is not null then rec.constant_name
            when rec.meta_kind is not null then split_part(rec.meta_kind::text, '.', 2)
            else null --todo error
        end
$$;

create view graphql.field as
    select
            t_parent.name parent_type,
            t_self.name type_,
            graphql.field_name(f, 'default') as name,
            f.is_not_null,
            f.is_array,
            f.is_array_not_null,
            f.is_arg,
            graphql.field_name(f_arg_parent, 'default') as parent_arg_field_name,
            f.default_value,
            f.description,
            f.column_name,
            f.column_type,
            f.parent_columns,
            f.local_columns,
            f.is_hidden_from_schema
        from
            graphql._field f
            join graphql.type t_parent
                on f.parent_type_id = t_parent.id
            join graphql.type t_self
                on f.type_id = t_self.id
            left join graphql._field f_arg_parent
                on f.parent_arg_field_id = f_arg_parent.id
        where
            -- Apply visibility rules
            case
                when f.constant_name = 'nodeId' then true
                when t_parent.entity is null then true
                when f.column_name is null then true
                when (
                    f.column_name is not null
                    and pg_catalog.has_column_privilege(current_user, t_parent.entity, f.column_name, 'SELECT')
                ) then true
                -- TODO: check if relationships are accessible
                when f.local_columns is not null then true
                else false
            end;
