create type graphql.field_meta_kind as enum (
    'Constant',
    'Query.collection',
    'Column',
    'Relationship.toMany',
    'Relationship.toOne',
    'OrderBy.Column',
    'Filter.Column',
    'Function',
    'Mutation.insert.one',
    'Mutation.delete',
    'Mutation.update',
    'UpdateSetArg',
    'ObjectArg',
    'AtMostArg'
);

create table graphql._field (
    id serial primary key,
    parent_type_id int references graphql._type(id),
    type_id  int not null references graphql._type(id) on delete cascade,
    meta_kind graphql.field_meta_kind default 'Constant',
    name text not null,
    constant_name text,

    -- args if is_arg, parent_arg_field_name is required
    parent_arg_field_id int references graphql._field(id) on delete cascade,
    default_value text,

    -- columns
    entity regclass,
    column_name text,
    column_attribute_num int,
    column_type regtype,

    -- relationships
    local_columns text[],
    foreign_columns text[],
    foreign_entity regclass,
    foreign_name_override text, -- from comment directive

    -- function extensions
    func regproc,

    -- internal flags
    is_not_null boolean not null,
    is_array boolean not null,
    is_array_not_null boolean,
    is_arg boolean default false,
    is_hidden_from_schema boolean default false,
    description text,

    check (meta_kind = 'Constant' and constant_name is not null or meta_kind <> 'Constant')
);

create index ix_graphql_field_type_id on graphql._field(type_id);
create index ix_graphql_field_parent_type_id on graphql._field(parent_type_id);
create index ix_graphql_field_parent_arg_field_id on graphql._field(parent_arg_field_id);
create index ix_graphql_field_meta_kind on graphql._field(meta_kind);
create index ix_graphql_field_entity on graphql._field(entity);


create or replace function graphql.field_name_for_column(entity regclass, column_name text)
    returns text
    immutable
    language sql
as $$
    select
        coalesce(
            graphql.comment_directive_name($1, $2),
            case
                -- If contains a capital letter, do not inflect
                when $2 <> lower($2) then $2
                else graphql.to_camel_case($2)
            end
        )
$$;


create or replace function graphql.field_name(rec graphql._field)
    returns text
    immutable
    language sql
as $$

    select
        case
            when rec.meta_kind = 'Constant' then rec.constant_name
            when rec.meta_kind in ('Column', 'OrderBy.Column', 'Filter.Column') then graphql.field_name_for_column(
                rec.entity,
                rec.column_name
            )
            when rec.meta_kind = 'Function' then coalesce(
                graphql.comment_directive_name(rec.func),
                graphql.to_camel_case(ltrim(graphql.to_function_name(rec.func), '_'))
            )
            when rec.meta_kind = 'Query.collection' then format('%sCollection', graphql.to_camel_case(graphql.type_name(rec.entity, 'Node')))
            when rec.meta_kind = 'Mutation.insert.one' then format('create%s', graphql.type_name(rec.entity, 'Node'))
            when rec.meta_kind = 'Mutation.update' then format('update%sCollection', graphql.type_name(rec.entity, 'Node'))
            when rec.meta_kind = 'Mutation.delete' then format('deleteFrom%sCollection', graphql.type_name(rec.entity, 'Node'))
            when rec.meta_kind = 'Relationship.toMany' then coalesce(
                rec.foreign_name_override,
                graphql.to_camel_case(graphql.type_name(rec.foreign_entity, 'Node')) || 'Collection'
            )
            when rec.meta_kind = 'Relationship.toOne' then coalesce(
                -- comment directive override
                rec.foreign_name_override,
                -- owner_id -> owner
                case array_length(rec.foreign_columns, 1) = 1 and rec.foreign_columns[1] like '%\_id'
                    when true then graphql.to_camel_case(left(rec.foreign_columns[1], -3))
                    else null
                end,
                -- default
                graphql.to_camel_case(graphql.type_name(rec.foreign_entity, 'Node'))
            )
            when rec.constant_name is not null then rec.constant_name
            else graphql.exception(format('could not determine field name, %s', $1))
        end
$$;


create function graphql.set_field_name()
    returns trigger
    language plpgsql
as $$
begin
    new.name = graphql.field_name(new);
    return new;
end;
$$;

create trigger on_insert_set_name
    before insert on graphql._field
    for each row execute procedure graphql.set_field_name();


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


    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_hidden_from_schema, description)
    values
        -- TODO parent type lookup from metakind
        (graphql.type_id('PageInfo'::graphql.meta_kind), graphql.type_id('Boolean'), 'hasPreviousPage', true,  false, null, false, null),
        (graphql.type_id('PageInfo'::graphql.meta_kind), graphql.type_id('Boolean'), 'hasNextPage',     true,  false, null, false, null),
        (graphql.type_id('PageInfo'::graphql.meta_kind), graphql.type_id('String'),  'startCursor',     false, false, null, false, null),
        (graphql.type_id('PageInfo'::graphql.meta_kind), graphql.type_id('String'),  'endCursor',       false, false, null, false, null);


    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, description, is_hidden_from_schema)

        select
            fs.field_meta_kind::graphql.field_meta_kind,
            conn.entity,
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
                    ('Constant', edge.id, node.id,                     'node',       false, false, null::boolean, null::text, null::text, null::text[], null::text[], false),
                    ('Constant', edge.id, graphql.type_id('String'),   'cursor',     true,  false, null, null, null, null, null, false),
                    ('Constant', conn.id, edge.id,                     'edges',      true,  true,  true, null, null, null, null, false),
                    ('Constant', conn.id, graphql.type_id('Int'),      'totalCount', true,  false, null, null, null, null, null, false),
                    ('Constant', conn.id, graphql.type_id('PageInfo'::graphql.meta_kind), 'pageInfo',   true,  false, null, null, null, null, null, false),
                    ('Query.collection', graphql.type_id('Query'::graphql.meta_kind), conn.id, null, false, false, null,
                        format('A pagable collection of type `%s`', graphql.type_name(conn.entity, 'Node')), null, null, null, false)
            ) fs(field_meta_kind, parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, description, column_name, foreign_columns, local_columns, is_hidden_from_schema)
        where
            conn.meta_kind = 'Connection'
            and edge.meta_kind = 'Edge'
            and node.meta_kind = 'Node';

    -- Object.__typename
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, constant_name, is_not_null, is_array, is_hidden_from_schema)
        select
            'Constant'::graphql.field_meta_kind,
            t.entity,
            t.id,
            graphql.type_id('String'),
            '__typename',
            true,
            false,
            true
        from
            graphql.type t
        where
            t.type_kind = 'OBJECT';


    -- Node
    -- Node.<column>
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, is_not_null, is_array, is_array_not_null, description, column_name, column_type, column_attribute_num, is_hidden_from_schema)
        select
            'Column' as meta_kind,
            gt.entity,
            gt.id parent_type_id,
            graphql.type_id(es.column_type) as type_id,
            es.is_not_null,
            es.is_array as is_array,
            es.is_not_null and graphql.sql_type_is_array(es.column_type) as is_array_not_null,
            null::text description,
            es.column_name as column_name,
            es.column_type as column_type,
            es.column_attribute_num,
            false as is_hidden_from_schema
        from
            graphql.type gt
            join graphql.entity_column es
                on gt.entity = es.entity
        where
            gt.meta_kind = 'Node';

    -- Node
    -- Extensibility via function taking record type
    -- Node.<function()>
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, is_not_null, is_array, is_array_not_null, description, is_hidden_from_schema, func)
        select
            'Function' as meta_kind,
            gt.entity,
            gt.id parent_type_id,
            graphql.type_id(pp.prorettype::regtype) as type_id,
            false as is_not_null,
            graphql.sql_type_is_array(pp.prorettype::regtype) as is_array,
            false as is_array_not_null,
            null::text description,
            false as is_hidden_from_schema,
            pp.oid::regproc as func
        from
            graphql.type gt
            join pg_class pc
                on gt.entity = pc.oid
            join pg_proc pp
                on pp.proargtypes[0] = pc.reltype
        where
            gt.meta_kind = 'Node'
            and pronargs = 1
            -- starts with underscore
            and graphql.to_function_name(pp.oid::regproc) like '\_%';

    -- Node.<relationship>
    insert into graphql._field(
        parent_type_id,
        type_id,
        entity,
        foreign_entity,
        meta_kind,
        is_not_null,
        is_array,
        is_array_not_null,
        description,
        foreign_columns,
        local_columns,
        foreign_name_override
    )
        select
            node.id parent_type_id,
            conn.id type_id,
            node.entity,
            rel.foreign_entity,
            case
                when (conn.meta_kind = 'Node' and rel.foreign_cardinality = 'ONE') then 'Relationship.toOne'
                when (conn.meta_kind = 'Connection' and rel.foreign_cardinality = 'MANY') then 'Relationship.toMany'
                else null
            end::graphql.field_meta_kind meta_kind,
            false as is_not_null, -- todo: reference column nullability
            false as is_array,
            null as is_array_not_null,
            null::text as description,
            rel.local_columns,
            rel.foreign_columns,
            rel.foreign_name_override
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
    insert into graphql._field(meta_kind, parent_type_id, type_id, is_not_null, is_array, is_array_not_null, column_name, column_type, column_attribute_num, entity, description)
        select
            'OrderBy.Column' meta_kind,
            gt.id parent_type,
            graphql.type_id('OrderByDirection'::graphql.meta_kind) as type_id,
            false is_not_null,
            false is_array,
            null is_array_not_null,
            ec.column_name,
            ec.column_type,
            ec.column_attribute_num,
            gt.entity,
            null::text description
        from
            graphql.type gt
            join graphql.entity_column ec
                on gt.entity = ec.entity
        where
            gt.meta_kind = 'OrderBy';


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
    insert into graphql._field(meta_kind, parent_type_id, type_id, is_not_null, is_array, column_name, column_attribute_num, entity, description)
        select distinct
            'Filter.Column'::graphql.field_meta_kind as meta_kind,
            gt.id parent_type_id,
            gt_scalar.id type_id,
            false is_not_null,
            false is_array,
            ec.column_name,
            ec.column_attribute_num,
            gt.entity,
            null::text description
        from
            graphql.type gt
            join graphql.entity_column ec
                on gt.entity = ec.entity
            join graphql.type gt_scalar
                on graphql.type_id(ec.column_type) = gt_scalar.graphql_type_id
                and gt_scalar.meta_kind = 'FilterType'
        where
            gt.meta_kind = 'FilterEntity';


    -- Arguments
    -- __Field(includeDeprecated)
    -- __enumValue(includeDeprecated)
    -- __InputFields(includeDeprecated)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, default_value, description)
    select distinct
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

    -- Connection(first, last)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
    select
        f.type_id as parent_type_id,
        graphql.type_id('Int') type_id,
        y.constant_name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.id parent_arg_field_id,
        y.description
    from
        graphql.type t
        inner join graphql._field f
            on t.id = f.type_id,
        lateral (
            values
                ('first', 'Query the first `n` records in the collection'),
                ('last',  'Query the last `n` records in the collection')
        ) y(constant_name, description)
    where
        t.meta_kind = 'Connection';

    -- Connection(before, after)
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
    select
        f.type_id as parent_type_id,
        graphql.type_id('Cursor') type_id,
        y.constant_name,
        false as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        f.id parent_arg_field_id,
        y.description
    from
        graphql.type t
        inner join graphql._field f
            on t.id = f.type_id,
        lateral (
            values
                ('before', 'Query values in the collection before the provided cursor'),
                ('after',  'Query values in the collection after the provided cursor')
        ) y(constant_name, description)
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
        'Sort order to apply to the collection' as description
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
        'Filters to apply to the results set when querying from the collection' as description
    from
        graphql.type t
        inner join graphql._field f
            on t.id = f.type_id
            and t.meta_kind = 'Connection'
        inner join graphql.type tt
            on t.entity = tt.entity
            and tt.meta_kind = 'FilterEntity';

    -- Mutation.insertAccount
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, is_not_null, is_array, is_array_not_null, description, is_hidden_from_schema)
        select
            fs.field_meta_kind::graphql.field_meta_kind,
            node.entity,
            graphql.type_id('Mutation'::graphql.meta_kind),
            fs.type_id,
            fs.is_not_null,
            fs.is_array,
            fs.is_array_not_null,
            fs.description,
            false as is_hidden_from_schema
        from
            graphql.type node,
            lateral (
                values
                    ('Mutation.insert.one', node.id, false, false, false, format('Creates a single `%s`', node.name))
            ) fs(field_meta_kind, type_id, is_not_null, is_array, is_array_not_null, description)
        where
            node.meta_kind = 'Node';

    -- Mutation.updateAccountCollection
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, is_not_null, is_array, is_array_not_null, description, is_hidden_from_schema)
        select
            fs.field_meta_kind::graphql.field_meta_kind,
            ret_type.entity,
            graphql.type_id('Mutation'::graphql.meta_kind),
            fs.type_id,
            fs.is_not_null,
            fs.is_array,
            fs.is_array_not_null,
            fs.description,
            false as is_hidden_from_schema
        from
            graphql.type ret_type,
            lateral (
                values
                    ('Mutation.update', ret_type.id, true,  false,  false,  'Updates zero or more records in the collection')
            ) fs(field_meta_kind, type_id, is_not_null, is_array, is_array_not_null, description)
        where
            ret_type.meta_kind = 'UpdateNodeResponse';

    -- Mutation.deleteFromAccountCollection
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, is_not_null, is_array, is_array_not_null, description, is_hidden_from_schema)
        select
            fs.field_meta_kind::graphql.field_meta_kind,
            ret_type.entity,
            graphql.type_id('Mutation'::graphql.meta_kind),
            fs.type_id,
            fs.is_not_null,
            fs.is_array,
            fs.is_array_not_null,
            fs.description,
            false as is_hidden_from_schema
        from
            graphql.type ret_type,
            lateral (
                values
                    ('Mutation.delete', ret_type.id, true,  false,  false,  'Deletes zero or more records from the collection')
            ) fs(field_meta_kind, type_id, is_not_null, is_array, is_array_not_null, description)
        where
            ret_type.meta_kind = 'DeleteNodeResponse';

    -- Mutation.insertAccount(object: ...)
    insert into graphql._field(meta_kind, parent_type_id, type_id, entity, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
        select
            x.meta_kind,
            f.type_id as parent_type_id,
            tt.id type_id,
            t.entity,
            'object' as constant_name,
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
                and f.meta_kind = 'Mutation.insert.one'
            inner join graphql.type tt
                on t.entity = tt.entity
                and tt.meta_kind = 'CreateNode',
            lateral (
                values
                    ('ObjectArg'::graphql.field_meta_kind, 'object')
            ) x(meta_kind, constant_name);

    -- Mutation.insertAccount(object: {<column> })
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description, column_name, column_type, column_attribute_num, is_hidden_from_schema)
        select
            'Column' as meta_kind,
            gf.entity,
            gf.type_id parent_type_id,
            graphql.type_id(ec.column_type) as type_id,
            false as is_not_null,
            graphql.sql_type_is_array(ec.column_type) as is_array,
            false as is_array_not_null,
            true as is_arg,
            gf.id as parent_arg_field_id,
            null::text description,
            ec.column_name,
            ec.column_type,
            ec.column_attribute_num,
            false as is_hidden_from_schema
        from
            graphql._field gf
            join graphql.entity_column ec
                on gf.entity = ec.entity
        where
            gf.meta_kind = 'ObjectArg'
            and not ec.is_generated -- skip generated columns
            and not ec.is_serial; -- skip (big)serial columns


    -- AccountUpdateResponse.affectedCount
    -- AccountUpdateResponse.records
    -- AccountDeleteResponse.affectedCount
    -- AccountDeleteResponse.records
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, description)
    select
        t.id parent_type_id,
        x.type_id,
        x.constant_name,
        x.is_not_null,
        x.is_array,
        x.is_array_not_null,
        x.description
    from
        graphql.type t
        join graphql.type t_base
            on t.entity = t_base.entity
            and t_base.meta_kind = 'Node',
        lateral (
            values
                ('records', t_base.id, true, true, true, 'Array of records impacted by the mutation'),
                ('affectedCount', graphql.type_id('Int'), true, false, null, 'Count of the records impacted by the mutation')
        ) x (constant_name, type_id, is_not_null, is_array, is_array_not_null, description)
    where
        t.meta_kind in ('DeleteNodeResponse', 'UpdateNodeResponse');


    -- Mutation.delete(... filter: {})
    -- Mutation.update(... filter: {})
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
        'Restricts the mutation''s impact to records matching the critera' as description
    from
        graphql._field f
        inner join graphql.type tt
            on f.entity = tt.entity
            and tt.meta_kind = 'FilterEntity'
    where
        f.meta_kind in ('Mutation.delete', 'Mutation.update');

    -- Mutation.delete(... atMost: Int!)
    -- Mutation.update(... atMost: Int!)
    insert into graphql._field(meta_kind, parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, is_arg, default_value, parent_arg_field_id, description)
    select
        'AtMostArg'::graphql.field_meta_kind,
        f.type_id as parent_type_id,
        graphql.type_id('Int'),
        'atMost' as constant_name,
        true as is_not_null,
        false as is_array,
        false as is_array_not_null,
        true as is_arg,
        '1' as default_value,
        f.id parent_arg_field_id,
        'The maximum number of records in the collection permitted to be affected' as description
    from
        graphql._field f
    where
        f.meta_kind in ('Mutation.delete', 'Mutation.update');

    -- Mutation.update(set: ...)
    insert into graphql._field(meta_kind, parent_type_id, type_id, entity, constant_name, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description)
        select
            'UpdateSetArg'::graphql.field_meta_kind,
            f.type_id as parent_type_id,
            tt.id type_id,
            f.entity,
            'set' as constant_name,
            true as is_not_null,
            false as is_array,
            false as is_array_not_null,
            true as is_arg,
            f.id parent_arg_field_id,
            'Fields that are set will be updated for all records matching the `filter`' as description
        from
            graphql._field f
            inner join graphql.type tt
                on tt.meta_kind = 'UpdateNode'
                and f.entity = tt.entity
            where
                f.meta_kind = 'Mutation.update';

    -- Mutation.update(set: {<column> })
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description, column_name, column_type, column_attribute_num, is_hidden_from_schema)
        select
            'Column' as meta_kind,
            gf.entity,
            gf.type_id parent_type_id,
            graphql.type_id(ec.column_type) as type_id,
            false as is_not_null,
            graphql.sql_type_is_array(ec.column_type) as is_array,
            false as is_array_not_null,
            true as is_arg,
            gf.id as parent_arg_field_id,
            null::text description,
            ec.column_name,
            ec.column_type,
            ec.column_attribute_num,
            false as is_hidden_from_schema
        from
            graphql._field gf
            join graphql.entity_column ec
                on gf.entity = ec.entity
        where
            gf.meta_kind = 'UpdateSetArg'
            and not ec.is_generated -- skip generated columns
            and not ec.is_serial; -- skip (big)serial columns


end;
$$;


create view graphql.field as
    select
        f.id,
        t_parent.name parent_type,
        t_self.name type_,
        f.name,
        f.is_not_null,
        f.is_array,
        f.is_array_not_null,
        f.is_arg,
        f_arg_parent.name as parent_arg_field_name,
        f.parent_arg_field_id,
        f.default_value,
        f.description,
        f.entity,
        f.column_name,
        f.column_type,
        f.column_attribute_num,
        f.foreign_columns,
        f.local_columns,
        f.func,
        f.is_hidden_from_schema,
        f.meta_kind
    from
        graphql._field f
        join graphql.type t_parent
            on f.parent_type_id = t_parent.id
        join graphql.type t_self
            on f.type_id = t_self.id
        left join graphql._field f_arg_parent
            on f.parent_arg_field_id = f_arg_parent.id
    where
        f.name ~ '^[_A-Za-z][_0-9A-Za-z]*$'
        -- Apply visibility rules
        and case
            when f.meta_kind = 'Mutation.insert.one' then (
                pg_catalog.has_any_column_privilege(current_user, f.entity, 'INSERT')
                and pg_catalog.has_any_column_privilege(current_user, f.entity, 'SELECT')
            )
            when f.meta_kind = 'Mutation.update' then (
                pg_catalog.has_any_column_privilege(current_user, f.entity, 'UPDATE')
                and pg_catalog.has_any_column_privilege(current_user, f.entity, 'SELECT')
            )
            when f.meta_kind = 'Mutation.delete' then (
                pg_catalog.has_table_privilege(current_user, f.entity, 'DELETE')
                and pg_catalog.has_any_column_privilege(current_user, f.entity, 'SELECT')
            )
            -- When an input column, make sure role has insert and permission
            when f_arg_parent.meta_kind = 'ObjectArg' then pg_catalog.has_column_privilege(
                current_user,
                f.entity,
                f.column_name,
                'INSERT'
            )
            -- When an input column, make sure role has insert and permission
            when f_arg_parent.meta_kind = 'UpdateSetArg' then pg_catalog.has_column_privilege(
                current_user,
                f.entity,
                f.column_name,
                'UPDATE'
            )
            when f.column_name is not null then pg_catalog.has_column_privilege(
                current_user,
                f.entity,
                f.column_name,
                'SELECT'
            )
            when f.func is not null then pg_catalog.has_function_privilege(
                current_user,
                f.func,
                'EXECUTE'
            )
            -- Check if relationship local and remote columns are selectable
            when f.local_columns is not null then (
                (
                    select
                        bool_and(
                            pg_catalog.has_column_privilege(
                                current_user,
                                f.entity,
                                x.col,
                                'SELECT'
                            )
                        )
                    from
                        unnest(f.foreign_columns) x(col)
                ) and (
                    select
                        bool_and(
                            pg_catalog.has_column_privilege(
                                current_user,
                                f.foreign_entity,
                                x.col,
                                'SELECT'
                            )
                        )
                    from
                        unnest(f.local_columns) x(col)
                )
            )
            when f.column_name is null then true
            else false
        end;
