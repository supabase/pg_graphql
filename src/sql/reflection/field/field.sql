create type graphql.field_meta_kind as enum (
    'PageInfo.hasNextPage',
    'PageInfo.hasPreviousPage',
    'PageInfo.startCursor',
    'PageInfo.endCursor'
);

create table graphql._field (
    id serial primary key,
    parent_type_id int references graphql._type(id),
    type_id  int not null references graphql._type(id) on delete cascade,
    constant_name text,
    -- internal flags
    is_not_null boolean not null,
    is_array boolean not null,
    is_array_not_null boolean,
    is_arg boolean default false,
    is_hidden_from_schema boolean default false,
    -- if is_arg, parent_arg_field_name is required
    parent_arg_field_id int references graphql._field(id) on delete cascade,
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


create or replace function graphql.field_name(rec graphql._field, dialect text = 'default')
    returns text
    immutable
    language sql
as $$
    -- TODO
    select
        case
            when rec.constant_name is not null then rec.constant_name
            when rec.meta_kind is not null then split_part(rec.meta_kind::text, '.', 2)
            else null --todo error
        end
$$;

create index ix_graphql_field_name_dialect_default on graphql._field(
    graphql.field_name(rec := _field, dialect := 'default'::text)
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


        -- Node
        -- Node.<column>
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, description, column_name, column_type, is_hidden_from_schema)
        select
            gt.id parent_type_id,
            graphql.type_id(pa.atttypid::regtype) as type_id,
            -- TODO
            graphql.to_camel_case(pa.attname::text) as constant_name,
            pa.attnotnull as is_not_null,
            graphql.sql_type_is_array(pa.atttypid::regtype) as is_array,
            pa.attnotnull and graphql.sql_type_is_array(pa.atttypid::regtype) as is_array_not_null,
            null::text description,
            pa.attname::text as column_name,
            pa.atttypid::regtype as column_type,
            false as is_hidden_from_schema
        from
            graphql.type gt
            join pg_attribute pa
                on gt.entity = pa.attrelid
        where
            gt.meta_kind = 'Node'
            and pa.attnum > 0
            and not pa.attisdropped;



        -- Node.<relationship>
        -- Node.<connection>
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, description, parent_columns, local_columns)
        select
            node.id parent_type_id,
            conn.id type_id,

            -- todo
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
            end as constant_name,

            -- todo: reference column nullability
            false as is_not_null,
            false as is_array,
            null as is_array_not_null,
            null::text as description,
            rel.local_columns,
            rel.foreign_columns
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
            node.meta_kind = 'Node';


        -- NodeOrderBy
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, column_name, column_type, description)
        select
            gt.id parent_type,
            graphql.type_id('OrderByDirection'::graphql.meta_kind) as type_id,
            -- todo
            graphql.to_camel_case(pa.attname::text) as constant_name,
            false is_not_null,
            false is_array,
            null is_array_not_null,
            -- todo why is this here?
            pa.attname::text as column_name,
            pa.atttypid::regtype as column_type,
            null::text description
        from
            graphql.type gt
            join pg_attribute pa
                on gt.entity = pa.attrelid
        where
            gt.meta_kind = 'OrderBy'
            and pa.attnum > 0
            and not pa.attisdropped;


        -- IntFilter {eq: ...}
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, description)
        select
            gt.id as parent_type_id,
            gt.graphql_type_id type_id,
            'eq' as constant_name,
            false,
            false,
            null::text as description
        from
            graphql.type gt -- IntFilter
        where
            gt.meta_kind = 'FilterType';

        -- AccountFilter(column eq)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, column_name, description)
        select distinct
            -- Account Filter
            gt.id parent_type_id,

            gt_scalar.id type_id,

            -- todo
            graphql.to_camel_case(pa.attname::text) as constant_name,

            false is_not_null,
            false is_array,
            pa.attname::text as column_name,
            -- todo populate?
            null::text description
        from
            graphql.type gt
            join pg_attribute pa
                on gt.entity = pa.attrelid
            join graphql.type gt_scalar
                on graphql.type_id(pa.atttypid::regtype) = gt_scalar.graphql_type_id
                and gt_scalar.meta_kind = 'FilterType'
        where
            gt.meta_kind = 'FilterEntity'
            and pa.attnum > 0
            and not pa.attisdropped;


    -- Arguments
    -- __Field(includeDeprecated)
    -- __enumValue(includeDeprecated)
    -- __InputFields(includeDeprecated)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, default_value, description)
    select
        f.type_id as parent_type_id,
        graphql.type_id('Boolean') as type_id,
        'includeDeprecated' as constant_name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.id as parent_arg_field_id,
        'f' as default_value,
        null::text as description
    from
        graphql._field f
        join graphql.type t
            on f.type_id = t.id
    where
        t.meta_kind in ('__Field', '__EnumValue', '__InputValue', '__Directive');


    -- __type(name)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
    select
        f.type_id as parent_type_id,
        graphql.type_id('String') type_id,
        'name' as constant_name,
        true as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.id parent_arg_field_id,
        null::text as description
    from
        graphql._field f
        join graphql.type t
            on f.type_id = t.id
        join graphql.type pt
            on f.parent_type_id = pt.id
    where
        t.meta_kind = '__Type'
        and pt.meta_kind = 'Query'
        and f.constant_name = '__type';

    -- Node(nodeId)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
    select
        f.type_id,
        graphql.type_id('ID'::graphql.meta_kind) type_id,
        -- todo
        'nodeId' as constant_name,
        true as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.id parent_arg_field_id,
        null as description
    from
        graphql.type t
        inner join graphql._field f
            on t.id = f.type_id
        join graphql.type pt
            on f.parent_type_id = pt.id
    where
        t.meta_kind = 'Node'
        and pt.meta_kind = 'Query';


    -- Connection(first, last)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
    select
        f.type_id as parent_type_id,
        graphql.type_id('Int') type_id,
        y.name_ as constant_name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.id parent_arg_field_id,
        null::text as description
    from
        graphql.type t
        inner join graphql._field f
            on t.id = f.type_id,
        lateral (select name_ from unnest(array['first', 'last']) x(name_)) y(name_)
    where
        t.meta_kind = 'Connection';

    -- Connection(before, after)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
    select
        f.type_id as parent_type_id,
        graphql.type_id('Cursor') type_id,
        y.name_ as constant_name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.id parent_arg_field_id,
        null as description
    from
        graphql.type t
        inner join graphql._field f
            on t.id = f.type_id,
        lateral (select name_ from unnest(array['before', 'after']) x(name_)) y(name_)
    where
        t.meta_kind = 'Connection';


    -- Connection(orderBy)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
    select
        f.type_id as parent_type_id,
        tt.id type_id,
        'orderBy' as constant_name,
        true as is_not_null,
        true as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.id parent_arg_field_name,
        null as description
    from
        graphql.type t
        inner join graphql._field f
            on t.id = f.type_id
            and t.meta_kind = 'Connection'
        inner join graphql.type tt
            on t.entity = tt.entity
            and tt.meta_kind = 'OrderBy';

    -- Connection(filter)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
    select
        f.type_id as parent_type_id,
        tt.id type_,
        'filter' as constant_name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.id parent_arg_field_id,
        null as description
    from
        graphql.type t
        inner join graphql._field f
            on t.id = f.type_id
            and t.meta_kind = 'Connection'
        inner join graphql.type tt
            on t.entity = tt.entity
            and tt.meta_kind = 'FilterEntity';

end;
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
