create schema if not exists graphql;
create or replace function graphql.jsonb_coalesce(val jsonb, default_ jsonb)
    returns jsonb
    strict
    immutable
    language sql
as $$
    select case
        when jsonb_typeof(val) = 'null' then default_
        else val
    end;
$$;
create or replace function graphql.jsonb_unnest_recursive_with_jsonpath(obj jsonb)
    returns table(jpath jsonpath, obj jsonb)
     language sql
as $$
/*
Recursively unrolls a jsonb object and arrays to scalars

    select
        *
    from
        graphql.jsonb_keys_recursive('{"id": [1, 2]}'::jsonb)


    | jpath   |       obj      |
    |---------|----------------|
    | $       | {"id": [1, 2]} |
    | $.id    | [1, 2]         |
    | $.id[0] | 1              |
    | $.id[1] | 2              |

*/
    with recursive _tree as (
        select
            obj,
            '$' as path_

        union all
        (
            with typed_values as (
                select
                    jsonb_typeof(obj) as typeof,
                    obj,
                    path_
                from
                    _tree
            )
            select
                v.val_,
                path_ || '.' || key_
            from
                typed_values,
                lateral jsonb_each(obj) v(key_, val_)
            where
                typeof = 'object'

            union all

            select
                elem,
                path_ || '[' || (elem_ix - 1 )::text || ']'
            from
                typed_values,
                lateral jsonb_array_elements(obj) with ordinality z(elem, elem_ix)
            where
                typeof = 'array'
      )
    )

    select
        path_::jsonpath,
        obj
    from
        _tree
    order by
        path_::text;
$$;
create or replace function graphql.slug()
    returns text
    language sql
    volatile
as $$
    select substr(md5(random()::text), 0, 12);
$$;
create or replace function graphql._first_agg(anyelement, anyelement)
    returns anyelement
    immutable
    strict
    language sql
as $$ select $1; $$;

create aggregate graphql.first(anyelement) (
    sfunc    = graphql._first_agg,
    stype    = anyelement,
    parallel = safe
);
create function graphql.is_array(regtype)
    returns boolean
    immutable
    language sql
as
$$
    select pg_catalog.format_type($1, null) like '%[]'
$$;
create function graphql.is_composite(regtype)
    returns boolean
    immutable
    language sql
as
$$
    select typrelid > 0 from pg_catalog.pg_type where oid = $1;
$$;
create or replace function graphql.primary_key_columns(entity regclass)
    returns text[]
    language sql
    immutable
    as
$$
    select
        coalesce(array_agg(pg_attribute.attname::text order by attrelid asc), '{}')
    from
        pg_index
        join pg_attribute
            on pg_attribute.attrelid = pg_index.indrelid
            and pg_attribute.attnum = any(pg_index.indkey)
    where
        pg_index.indrelid = entity
        and pg_index.indisprimary
$$;
create or replace function graphql.primary_key_types(entity regclass)
    returns regtype[]
    language sql
    immutable
    as
$$
    select
        coalesce(array_agg(pg_attribute.atttypid::regtype order by attrelid asc), '{}')
    from
        pg_index
        join pg_attribute
            on pg_attribute.attrelid = pg_index.indrelid
            and pg_attribute.attnum = any(pg_index.indkey)
    where
        pg_index.indrelid = entity
        and pg_index.indisprimary
$$;
create materialized view graphql.entity as
    select
        pc.oid::regclass as entity
    from
        pg_class pc
        join pg_index pi
            on pc.oid = pi.indrelid
    where
        relkind = ANY (ARRAY['r', 'p'])
        and not relnamespace = ANY (ARRAY[
            'information_schema'::regnamespace,
            'pg_catalog'::regnamespace,
            'graphql'::regnamespace
        ])
        -- require a primary key (for pagination)
        and pi.indisprimary;


create materialized view graphql.entity_column as
    select
        e.entity,
        pa.attname::text as column_name,
        pa.atttypid::regtype as column_type,
        graphql.is_array(pa.atttypid::regtype) is_array,
        graphql.is_composite(pa.atttypid::regtype) is_composite,
        pa.attnotnull as is_not_null,
        not pa.attgenerated = '' as is_generated,
        pg_get_serial_sequence(e.entity::text, pa.attname) is not null as is_serial,
        pa.attnum as column_attribute_num
    from
        graphql.entity e
        join pg_attribute pa
            on e.entity = pa.attrelid
    where
        pa.attnum > 0
        and not pa.attisdropped
    order by
        entity,
        attnum;

create index ix_entity_column_entity_column_name
    on graphql.entity_column(entity, column_name);


create materialized view graphql.entity_unique_columns as
    select distinct
        ec.entity,
        pi.indexrelid::regclass::name index_name,
        array_agg(ec.column_name order by array_position(pi.indkey, ec.column_attribute_num)) unique_column_set
    from
        graphql.entity_column ec
        join pg_index pi
            on ec.entity = pi.indrelid
            and ec.column_attribute_num = any(pi.indkey)
    where
        pi.indisunique
        and pi.indisready
        and pi.indisvalid
        and pi.indpred is null -- exclude partial indexes
    group by
        ec.entity,
        pi.indexrelid;


create function graphql.column_set_is_unique(regclass, columns text[])
    returns bool
    language sql
    immutable
as $$
    select exists(
        select
            1
        from
            graphql.entity_unique_columns euc
        where
            euc.entity = $1
            -- unique set is contained by columns list
            and euc.unique_column_set <@ $2
    )
$$;
create function graphql.to_type_name(regtype)
    returns text
    language sql
    immutable
as
$$ select coalesce(nullif(split_part($1::text, '.', 2), ''), $1::text) $$;
create function graphql.to_function_name(regproc)
    returns text
    language sql
    stable
as
$$
    select
        proname
    from
        pg_proc
    where
        oid = $1::oid
$$;
create function graphql.to_regclass(schema_ text, name_ text)
    returns regclass
    language sql
    immutable
as
$$ select (quote_ident(schema_) || '.' || quote_ident(name_))::regclass; $$;
create function graphql.to_table_name(regclass)
    returns text
    language sql
    immutable
as
$$
    with x(maybe_quoted_name) as (
         select
            coalesce(nullif(split_part($1::text, '.', 2), ''), $1::text)
    )
    select
        case
            when maybe_quoted_name like '"%"' then substring(
                maybe_quoted_name,
                2,
                character_length(maybe_quoted_name)-2
            )
            else maybe_quoted_name
        end
    from
        x
$$;
create function graphql.to_camel_case(text)
    returns text
    language sql
    immutable
as
$$
select
    string_agg(
        case
            when part_ix = 1 then format(
                '%s%s',
                lower(left(part,1)),
                right(part, character_length(part)-1)
            )
            else initcap(part)
        end, '')
from
    unnest(string_to_array($1, '_')) with ordinality x(part, part_ix)
$$;
create or replace function graphql.alias_or_name_literal(field jsonb)
    returns text
    language sql
    immutable
    strict
as $$
    select coalesce(field -> 'alias' ->> 'value', field -> 'name' ->> 'value')
$$;
create or replace function graphql.arg_to_jsonb(
    arg jsonb, -- has
    variables jsonb default '{}'
)
    returns jsonb
    language sql
    immutable
    as
$$
    select
        case arg ->> 'kind'
            when 'Argument'     then graphql.arg_to_jsonb(arg -> 'value', variables)
            when 'IntValue'     then to_jsonb((arg ->> 'value')::int)
            when 'FloatValue'   then to_jsonb((arg ->> 'value')::float)
            when 'BooleanValue' then to_jsonb((arg ->> 'value')::bool)
            when 'StringValue'  then to_jsonb(arg ->> 'value')
            when 'EnumValue'    then to_jsonb(arg ->> 'value')
            when 'ListValue'    then (
                select
                    jsonb_agg(
                        graphql.arg_to_jsonb(je.x, variables)
                    )
                from
                    jsonb_array_elements((arg -> 'values')) je(x)
            )
            when 'ObjectField'  then (
                jsonb_build_object(
                    arg -> 'name' -> 'value',
                    graphql.arg_to_jsonb(arg -> 'value', variables)
                )
            )
            when 'ObjectValue'  then (
                select
                    jsonb_object_agg(
                        je.elem -> 'name' ->> 'value',
                        graphql.arg_to_jsonb(je.elem -> 'value', variables)
                    )
                from
                    jsonb_array_elements((arg -> 'fields')) je(elem)
            )
            when 'Variable'     then (
                case
                    -- null value should be treated as missing in all cases.
                    when jsonb_typeof((variables -> (arg -> 'name' ->> 'value'))) = 'null' then null
                    else (variables -> (arg -> 'name' ->> 'value'))
                end
            )
        else (
            case
                when arg is null then null
                else  graphql.exception('unhandled argument kind')::jsonb
            end
        )
        end;
$$;


create or replace function graphql.arg_coerce_list(arg jsonb)
returns jsonb
    language sql
    immutable
    as
$$
    -- Wraps jsonb value with a list if its not already a list
    -- If null, returns null
    select
        case
            when jsonb_typeof(arg) is null then arg -- sql null
            when jsonb_typeof(arg) = 'null' then null-- json null
            when jsonb_typeof(arg) = 'array' then arg
            else jsonb_build_array(arg)
        end;
$$;
create or replace function graphql.ast_pass_fragments(ast jsonb, fragment_defs jsonb = '{}')
    returns jsonb
    language sql
    immutable
as $$
/*
Recursively replace fragment spreads with the fragment definition's selection set
*/
    select
        case
            when jsonb_typeof(ast) = 'object' then
                    (
                        select
                            jsonb_object_agg(key_, graphql.ast_pass_fragments(value_, fragment_defs))
                        from
                            jsonb_each(ast) x(key_, value_)
                    )
            when jsonb_typeof(ast) = 'array' then
                coalesce(
                    (
                        select
                            jsonb_agg(graphql.ast_pass_fragments(value_, fragment_defs))
                        from
                            jsonb_array_elements(ast) x(value_)
                        where
                            value_ ->> 'kind' <> 'FragmentSpread'
                    ),
                    '[]'::jsonb
                )
                ||
                coalesce(
                    (
                        select
                            jsonb_agg(
                                frag_selection
                            )
                        from
                            jsonb_array_elements(ast) x(value_),
                            lateral(
                                select jsonb_path_query_first(
                                    fragment_defs,
                                    ('$ ? (@.name.value == "'|| (value_ -> 'name' ->> 'value') || '")')::jsonpath
                                ) as raw_frag_def
                            ) x1,
                            lateral (
                                -- Nested fragments are possible
                                select graphql.ast_pass_fragments(raw_frag_def, fragment_defs) as frag
                            ) x2,
                            lateral (
                                select y1.frag_selection
                                from jsonb_array_elements(frag -> 'selectionSet' -> 'selections') y1(frag_selection)
                            ) x3
                        where
                            value_ ->> 'kind' = 'FragmentSpread'
                    ),
                    '[]'::jsonb
                )
            else
                ast
        end;
$$;
create function graphql.ast_pass_strip_loc(body jsonb)
returns jsonb
language sql
immutable
as $$
/*
Remove a 'loc' key from a jsonb object by name
*/
select
    regexp_replace(
        body::text,
        '"loc":\s*\{\s*("end"|"start")\s*:\s*\{\s*("line"|"column")\s*:\s*\d+,\s*("line"|"column")\s*:\s*\d+\s*},\s*("end"|"start")\s*:\s*\{\s*("line"|"column")\s*:\s*\d+,\s*("line"|"column")\s*:\s*\d+\s*}\s*},'::text,
        '',
        'g'
    )::jsonb
$$;
create or replace function graphql.is_literal(field jsonb)
    returns boolean
    immutable
    strict
    language sql
as $$
    select not graphql.is_variable(field)
$$;
create or replace function graphql.is_variable(field jsonb)
    returns boolean
    immutable
    strict
    language sql
as $$
    select (field ->> 'kind') = 'Variable'
$$;
create or replace function graphql.name_literal(ast jsonb)
    returns text
    immutable
    language sql
as $$
    select ast -> 'name' ->> 'value';
$$;
create type graphql.parse_result AS (
    ast text,
    error text
);

create function graphql.parse(text)
    returns graphql.parse_result
    language c
    immutable
as 'pg_graphql', 'parse';
create or replace function graphql.value_literal(ast jsonb)
    returns text
    immutable
    language sql
as $$
    select ast -> 'value' ->> 'value';
$$;
create or replace function graphql.exception(message text)
    returns text
    language plpgsql
as $$
begin
    raise exception using errcode='22000', message=message;
end;
$$;
create or replace function graphql.exception_required_argument(arg_name text)
    returns text
    language plpgsql
as $$
begin
    raise exception using errcode='22000', message=format('Argument %L is required', arg_name);
end;
$$;
create or replace function graphql.exception_unknown_field(field_name text, type_name text)
    returns text
    language plpgsql
as $$
begin
    raise exception using errcode='22000', message=format('Unknown field %L on type %L', field_name, type_name);
end;
$$;

create or replace function graphql.exception_unknown_field(field_name text)
    returns text
    language plpgsql
as $$
begin
    raise exception using errcode='22000', message=format('Unknown field %L', field_name);
end;
$$;
create type graphql.column_order_direction as enum ('asc', 'desc');


create type graphql.column_order_w_type as(
    column_name text,
    direction graphql.column_order_direction,
    nulls_first bool,
    type_ regtype
);


create or replace function graphql.reverse(
    column_orders graphql.column_order_w_type[]
)
    returns graphql.column_order_w_type[]
    immutable
    language sql
as $$
    select
        array_agg(
            (
                (co).column_name,
                case
                    when (co).direction = 'asc'::graphql.column_order_direction then 'desc'
                    when (co).direction = 'desc'::graphql.column_order_direction then 'asc'
                    else graphql.exception('Unreachable exception in orderBy clause')
                end,
                case
                    when (co).nulls_first then false
                    else true
                end,
                (co).type_
            )::graphql.column_order_w_type
        )
    from
        unnest(column_orders) co
$$;



create or replace function graphql.to_cursor_clause(
    alias_name text,
    column_orders graphql.column_order_w_type[]
)
    returns text
    immutable
    language sql
as $$
/*
    -- Produces the SQL to create a cursor
    select graphql.to_cursor_clause(
        'abc',
        array[('email', 'asc', true, 'text'::regtype), ('id', 'asc', false, 'int'::regtype)]::graphql.column_order[]
    )
*/
    select
        format(
            'jsonb_build_array(%s)',
            (
                string_agg(
                    format(
                        'to_jsonb(%I.%I)',
                        alias_name,
                        co.elems
                    ),
                    ', '
                )
            )
        )
    from
        unnest(column_orders) co(elems)
$$;


create or replace function graphql.encode(jsonb)
    returns text
    language sql
    immutable
as $$
/*
    select graphql.encode('("{""(email,asc,t)"",""(id,asc,f)""}","[""aardvark@x.com"", 1]")'::graphql.cursor)
*/
    select encode(convert_to($1::text, 'utf-8'), 'base64')
$$;

create or replace function graphql.decode(text)
    returns jsonb
    language sql
    immutable
    strict
as $$
/*
    select graphql.decode(graphql.encode('("{""(email,asc,t)"",""(id,asc,f)""}","[""aardvark@x.com"", 1]")'::graphql.cursor))
*/
    select convert_from(decode($1, 'base64'), 'utf-8')::jsonb
$$;


create or replace function graphql.cursor_where_clause(
    block_name text,
    column_orders graphql.column_order_w_type[],
    cursor_ text,
    cursor_var_ix int,
    depth_ int = 1
)
    returns text
    immutable
    language sql
as $$
    with v as (
        select
            format(
                '((graphql.decode(%s)) ->> %s)::%s',
                case
                    when cursor_ is not null then format('%L', cursor_)
                    when cursor_var_ix is not null then format('$%s', cursor_var_ix)
                    -- both are null
                    else 'null'
                end,
                depth_ - 1,
                case
                    -- Solves issue with `select 0.996461 > '0.996461'::real` being true resulting in failed pagination
                    when (column_orders[depth_]).type_ in ('real'::regtype, 'double precision'::regtype) then 'numeric'::regtype
                    else (column_orders[depth_]).type_
                end
            ) as val
    )
    select
        case
            when array_length(column_orders, 1) > (depth_ - 1)
                then format(
                '(
                    (     %I.%I %s %s or (%I.%I is not null and %s is null and %s))
                     or ((%I.%I = %s  or (%I.%I is null and %s is null))            and %s)
                )',
                block_name,
                column_orders[depth_].column_name,
                case when column_orders[depth_].direction = 'asc' then '>' else '<' end,
                v.val,
                block_name,
                column_orders[depth_].column_name,
                v.val,
                case column_orders[depth_].nulls_first when true then 'true' else 'false' end,
                --
                block_name,
                column_orders[depth_].column_name,
                v.val,
                block_name,
                column_orders[depth_].column_name,
                v.val,
                graphql.cursor_where_clause(
                    block_name,
                    column_orders,
                    cursor_,
                    cursor_var_ix,
                    depth_ + 1
                )
            )
            else 'false'
        end
    from
        v;
$$;
create function graphql.comment_directive(comment_ text)
    returns jsonb
    language sql
as $$
    /*
    comment on column public.account.name is '@graphql.name: myField'
    */
    select
        (
            regexp_matches(
                comment_,
                '@graphql\((.+?)\)',
                'g'
            )
        )[1]::jsonb
$$;

-------------------
-- Read Comments --
-------------------

create function graphql.comment(regclass)
    returns text
    language sql
as $$
    select pg_catalog.obj_description($1::oid, 'pg_class')
$$;


create function graphql.comment(regtype)
    returns text
    language sql
as $$
    select pg_catalog.obj_description($1::oid, 'pg_type')
$$;

create function graphql.comment(regproc)
    returns text
    language sql
as $$
    select pg_catalog.obj_description($1::oid, 'pg_proc')
$$;

create function graphql.comment(regnamespace)
    returns text
    language sql
as $$
    select pg_catalog.obj_description($1::oid, 'pg_namespace')
$$;

create function graphql.comment(regclass, column_name text)
    returns text
    language sql
as $$
    select
        pg_catalog.col_description($1::oid, attnum)
    from
        pg_attribute
    where
        attrelid = $1::oid
        and attname = column_name::name
        and attnum > 0
        and not attisdropped
$$;

----------------
-- Directives --
----------------

-- Schema Level

create function graphql.comment_directive_inflect_names(regnamespace)
    returns bool
    language sql
as $$
    select
        case
            when (graphql.comment_directive(graphql.comment($1)) -> 'inflect_names') = to_jsonb(true) then true
            else false
        end
$$;

-- Table Level

create function graphql.comment_directive_name(regclass)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1)) ->> 'name'
$$;

create function graphql.comment_directive_totalCount_enabled(regclass)
    -- Should totalCount be enabled on connections?
    -- @graphql({"totalCount": {"enabled": true}})
    returns boolean
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1)) -> 'totalCount' -> 'enabled' = to_jsonb(true)
$$;

-- Column Level

create function graphql.comment_directive_name(regclass, column_name text)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1, column_name)) ->> 'name'
$$;

-- Type Level

create function graphql.comment_directive_name(regtype)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1)) ->> 'name'
$$;

-- Function Level

create function graphql.comment_directive_name(regproc)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1)) ->> 'name'
$$;
create type graphql.cardinality as enum ('ONE', 'MANY');
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


    -- Custom Scalar
    'Date',
    'Time',
    'Datetime',
    'BigInt',
    'UUID',
    'JSON',

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
    'InsertNode',
    'UpdateNode',
    'InsertNodeResponse',
    'UpdateNodeResponse',
    'DeleteNodeResponse',

-- GraphQL Type Derived
    'FilterType',

-- Enum Derived
    'Enum'
);
-- https://github.com/graphql/graphql-js/blob/main/src/type/introspection.ts#L197
create type graphql.type_kind as enum (
    'SCALAR',
    'OBJECT',
    'INTERFACE',
    'UNION',
    'ENUM',
    'INPUT_OBJECT',
    'LIST',
    'NON_NULL'
);
create table graphql._type (
    id serial primary key,
    type_kind graphql.type_kind not null,
    meta_kind graphql.meta_kind not null,
    is_builtin bool not null default false,
    constant_name text,
    name text not null,
    entity regclass,
    graphql_type_id int references graphql._type(id),
    enum regtype,
    description text,
    unique (meta_kind, entity),
    check (entity is null or graphql_type_id is null)
);

create index ix_graphql_type_name on graphql._type(name);
create index ix_graphql_type_type_kind on graphql._type(type_kind);
create index ix_graphql_type_meta_kind on graphql._type(meta_kind);
create index ix_graphql_type_graphql_type_id on graphql._type(graphql_type_id);


create or replace function graphql.inflect_type_default(text)
    returns text
    language sql
    immutable
as $$
    select replace(initcap($1), '_', '');
$$;


create function graphql.type_name(rec graphql._type)
    returns text
    immutable
    language sql
as $$
    with name_override as (
        select
            case
                when rec.entity is not null then coalesce(
                    -- Explicit name has firts priority
                    graphql.comment_directive_name(rec.entity),
                    -- When the schema has "inflect_names: true then inflect. otherwise, use table name
                    case graphql.comment_directive_inflect_names(current_schema::regnamespace)
                        when true then graphql.inflect_type_default(graphql.to_table_name(rec.entity))
                        else graphql.to_table_name(rec.entity)
                    end
                )
                else null
            end as base_type_name
    )
    select
        case
            when (rec).is_builtin then rec.meta_kind::text
            when rec.meta_kind='Node'         then base_type_name
            when rec.meta_kind='InsertNode'   then format('%sInsertInput',base_type_name)
            when rec.meta_kind='UpdateNode'   then format('%sUpdateInput',base_type_name)
            when rec.meta_kind='UpdateNodeResponse' then format('%sUpdateResponse',base_type_name)
            when rec.meta_kind='InsertNodeResponse' then format('%sInsertResponse',base_type_name)
            when rec.meta_kind='DeleteNodeResponse' then format('%sDeleteResponse',base_type_name)
            when rec.meta_kind='Edge'         then format('%sEdge',       base_type_name)
            when rec.meta_kind='Connection'   then format('%sConnection', base_type_name)
            when rec.meta_kind='OrderBy'      then format('%sOrderBy',    base_type_name)
            when rec.meta_kind='FilterEntity' then format('%sFilter',     base_type_name)
            when rec.meta_kind='FilterType'        then format('%sFilter',     graphql.type_name(rec.graphql_type_id))
            when rec.meta_kind='OrderByDirection'  then rec.meta_kind::text
            when rec.meta_kind='PageInfo'     then rec.meta_kind::text
            when rec.meta_kind='Cursor'       then rec.meta_kind::text
            when rec.meta_kind='Query'        then rec.meta_kind::text
            when rec.meta_kind='Mutation'     then rec.meta_kind::text
            when rec.meta_kind='Enum'         then coalesce(
                graphql.comment_directive_name(rec.enum),
                graphql.inflect_type_default(graphql.to_type_name(rec.enum))
            )
            else graphql.exception('could not determine type name')
        end
    from
        name_override
$$;

create function graphql.type_name(type_id int)
    returns text
    immutable
    language sql
as $$
    select
        graphql.type_name(rec)
    from
        graphql._type rec
    where
        id = $1;
$$;

create function graphql.type_name(regclass, graphql.meta_kind)
    returns text
    immutable
    language sql
as $$
    select
        graphql.type_name(rec)
    from
        graphql._type rec
    where
        entity = $1
        and meta_kind = $2
$$;

create function graphql.set_type_name()
    returns trigger
    language plpgsql
as $$
begin
    new.name = coalesce(
        new.constant_name,
        graphql.type_name(new)
    );
    return new;
end;
$$;

create trigger on_insert_set_name
    before insert on graphql._type
    for each row execute procedure graphql.set_type_name();
create view graphql.type as
    select
        id,
        type_kind,
        meta_kind,
        is_builtin,
        constant_name,
        name,
        entity,
        graphql_type_id,
        enum,
        description
    from
        graphql._type t
        left join pg_class pc
            on t.entity = pc.oid
        left join pg_type tp
            on t.enum = tp.oid
    where
        t.name ~ '^[_A-Za-z][_0-9A-Za-z]*$'
        and (
            t.entity is null
            or (
                case
                    when meta_kind in (
                        'Node',
                        'Edge',
                        'Connection',
                        'OrderBy',
                        'FilterEntity',
                        'InsertNodeResponse',
                        'UpdateNodeResponse',
                        'DeleteNodeResponse'
                    )
                        then
                            pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'SELECT'
                            )
                    when meta_kind = 'FilterEntity'
                        then
                            pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'SELECT'
                            ) or pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'UPDATE'
                            ) or pg_catalog.has_table_privilege(
                                current_user,
                                t.entity,
                                'DELETE'
                            )
                    when meta_kind = 'InsertNode'
                        then
                            pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'INSERT'
                            ) and pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'SELECT'
                            )
                    when meta_kind = 'UpdateNode'
                        then
                            pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'UPDATE'
                            ) and pg_catalog.has_any_column_privilege(
                                current_user,
                                t.entity,
                                'SELECT'
                            )
                    else true
                end
                -- ensure regclass' schema is on search_path
                and pc.relnamespace::regnamespace::name = any(current_schemas(false))
            )
        )
        and (
            t.enum is null
            or (
                pg_catalog.has_type_privilege(
                    current_user,
                    t.enum,
                    'USAGE'
                )
                -- ensure enum's schema is on search_path
                and tp.typnamespace::regnamespace::name = any(current_schemas(false))
            )
        );
create function graphql.sql_type_to_graphql_type(regtype)
    returns text
    language sql
as
$$
    select
        case $1
            when 'smallint'          ::regtype then 'Int'
            when 'smallint[]'        ::regtype then 'Int'

            when 'integer'           ::regtype then 'Int'
            when 'integer[]'         ::regtype then 'Int'

            when 'bigint'            ::regtype then 'BigInt'
            when 'bigint[]'          ::regtype then 'BigInt'

            when 'boolean'           ::regtype then 'Boolean'
            when 'boolean[]'         ::regtype then 'Boolean'

            when 'real'              ::regtype then 'Float'
            when 'real[]'            ::regtype then 'Float'

            when 'double precision'  ::regtype then 'Float'
            when 'double precision[]'::regtype then 'Float'

            when 'json'              ::regtype  then 'JSON'
            when 'json[]'            ::regtype  then 'JSON'

            when 'jsonb'             ::regtype  then 'JSON'
            when 'jsonb[]'           ::regtype  then 'JSON'

            when 'uuid'              ::regtype  then 'UUID'
            when 'uuid[]'            ::regtype  then 'UUID'

            when 'date'              ::regtype  then 'Date'
            when 'date[]'            ::regtype  then 'Date'

            when 'time'              ::regtype  then 'Time'
            when 'time[]'            ::regtype  then 'Time'

            when 'timestamp'         ::regtype then 'Datetime'
            when 'timestamp[]'       ::regtype then 'Datetime'

            when 'timestamptz'       ::regtype then 'Datetime'
            when 'timestamptz[]'     ::regtype then 'Datetime'
        else 'String'
    end;
$$;




create function graphql.type_id(regtype)
    returns int
    immutable
    language sql
as
$$
    select
        graphql.type_id(graphql.sql_type_to_graphql_type($1))
$$;
create or replace function graphql.rebuild_types()
    returns void
    language plpgsql
    as
$$
begin
    alter sequence graphql._type_id_seq restart with 1;

    insert into graphql._type(type_kind, meta_kind, is_builtin, description)
        select
            type_kind::graphql.type_kind,
            meta_kind::graphql.meta_kind,
            true::bool,
            x.description
        from (
            values
            ('ID',       'SCALAR', true, null),
            ('Int',      'SCALAR', true, null),
            ('Float',    'SCALAR', true, null),
            ('String',   'SCALAR', true, null),
            ('Boolean',  'SCALAR', true, null),
            ('Date',     'SCALAR', true, null),
            ('Time',     'SCALAR', true, null),
            ('Datetime', 'SCALAR', true, null),
            ('BigInt',   'SCALAR', true, null),
            ('UUID',     'SCALAR', true, null),
            ('JSON',     'SCALAR', true, null),
            ('Cursor',   'SCALAR', false, null),
            ('Query',    'OBJECT', false, 'The root type for querying data'),
            ('Mutation', 'OBJECT', 'false', 'The root type for creating and mutating data'),
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


    insert into graphql._type(type_kind, meta_kind, description, graphql_type_id)
       values
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Int"',      graphql.type_id('Int')),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Float"',    graphql.type_id('Float')),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "String"',   graphql.type_id('String')),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Boolean"',  graphql.type_id('Boolean')),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Date"',     graphql.type_id('Date')),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Time"',     graphql.type_id('Time')),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Datetime"', graphql.type_id('Datetime')),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "BigInt"',   graphql.type_id('BigInt')),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "UUID"',     graphql.type_id('UUID')),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "JSON"',     graphql.type_id('JSON'));


    -- Query types
    insert into graphql._type(type_kind, meta_kind, description, entity)
        select
           x.*
        from
            graphql.entity ent,
            lateral (
                values
                    ('OBJECT'::graphql.type_kind, 'Node'::graphql.meta_kind, null::text, ent.entity),
                    ('OBJECT',                    'Edge',                    null,       ent.entity),
                    ('OBJECT',                    'Connection',              null,       ent.entity),
                    ('INPUT_OBJECT',              'OrderBy',                 null,       ent.entity),
                    ('INPUT_OBJECT',              'FilterEntity',            null,       ent.entity),
                    ('INPUT_OBJECT',              'InsertNode',              null,       ent.entity),
                    ('INPUT_OBJECT',              'UpdateNode',              null,       ent.entity),
                    ('OBJECT',                    'InsertNodeResponse',      null,       ent.entity),
                    ('OBJECT',                    'UpdateNodeResponse',      null,       ent.entity),
                    ('OBJECT',                    'DeleteNodeResponse',      null,       ent.entity)
            ) x(type_kind, meta_kind, description, entity);


    insert into graphql._type(type_kind, meta_kind, description, enum)
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
create materialized view graphql.relationship as
    with rels as materialized (
        select
            const.conname as constraint_name,
            const.oid as constraint_oid,
            e.entity as local_entity,
            array_agg(local_.attname::text order by l.col_ix asc) as local_columns,
            case graphql.column_set_is_unique(e.entity, array_agg(local_.attname::text))
                when true then 'ONE'
                else 'MANY'
            end::graphql.cardinality as local_cardinality,
            const.confrelid::regclass as foreign_entity,
            array_agg(ref_.attname::text order by r.col_ix asc) as foreign_columns,
            'ONE'::graphql.cardinality as foreign_cardinality,
            com.comment_,
            graphql.comment_directive(com.comment_) ->> 'local_name' as local_name_override,
            graphql.comment_directive(com.comment_) ->> 'foreign_name' as foreign_name_override
        from
            graphql.entity e
            join pg_constraint const
                on const.conrelid = e.entity
            join pg_attribute local_
                on const.conrelid = local_.attrelid
                and local_.attnum = any(const.conkey)
            join pg_attribute ref_
                on const.confrelid = ref_.attrelid
                and ref_.attnum = any(const.confkey),
            unnest(const.conkey) with ordinality l(col, col_ix)
            join unnest(const.confkey) with ordinality r(col, col_ix)
                on l.col_ix = r.col_ix,
            lateral (
                select pg_catalog.obj_description(const.oid, 'pg_constraint') body
            ) com(comment_)
        where
            const.contype = 'f'
        group by
            e.entity,
            com.comment_,
            const.oid,
            const.conname,
            const.confrelid
    )
    select
        constraint_name,
        local_entity,
        local_columns,
        local_cardinality,
        foreign_entity,
        foreign_columns,
        foreign_cardinality,
        foreign_name_override
    from
        rels
    union all
    select
        constraint_name,
        foreign_entity,
        foreign_columns,
        foreign_cardinality,
        local_entity,
        local_columns,
        local_cardinality,
        local_name_override
    from
        rels;
create type graphql.field_meta_kind as enum (
    'Constant',
    'Query.collection',
    'Column',
    'Relationship.toMany',
    'Relationship.toOne',
    'OrderBy.Column',
    'Filter.Column',
    'Function',
    'Mutation.insert',
    'Mutation.delete',
    'Mutation.update',
    'UpdateSetArg',
    'ObjectsArg',
    'AtMostArg',
    'Query.heartbeat',
    '__Typename'
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
    stable
    language sql
as $$
    select
        coalesce(
            graphql.comment_directive_name($1, $2),
            case graphql.comment_directive_inflect_names(current_schema::regnamespace)
                when true then graphql.to_camel_case($2)
                else $2
            end
        )
$$;

create or replace function graphql.lowercase_first_letter(text)
    returns text
    immutable
    strict
    language sql
as $$
    select format(
        '%s%s',
        substring(lower($1), 1, 1),
        substring($1, 2, 999)
    );
$$;


create or replace function graphql.field_name_for_to_many(foreign_entity regclass, foreign_name_override text)
    returns text
    stable
    language sql
as $$
    select
        coalesce(
            foreign_name_override,
            format(
                '%sCollection',
                graphql.lowercase_first_letter(
                    graphql.type_name(foreign_entity, 'Node')
                )
            )
        );
$$;


create or replace function graphql.field_name_for_query_collection(entity regclass)
    returns text
    stable
    language sql
as $$
    select
        format(
            '%sCollection',
            graphql.lowercase_first_letter(
                coalesce(
                    graphql.comment_directive_name(entity),
                    graphql.type_name(entity, 'Node')
                )
            )
        );
$$;


create or replace function graphql.field_name_for_to_one(foreign_entity regclass, foreign_name_override text, foreign_columns text[])
    returns text
    stable
    language plpgsql
as $$
declare
    is_inflection_on bool = graphql.comment_directive_inflect_names(current_schema::regnamespace);

    has_req_suffix text = case is_inflection_on
        when true then '\_id'
        when false then 'Id'
    end;

    req_suffix_len int = case is_inflection_on
        when true then 3
        when false then 2
    end;

    -- owner_id -> owner (inflection off); ownerId -> owner (inflection on)
    is_single_col_ending_id bool = (
        array_length(foreign_columns, 1) = 1
        and foreign_columns[1] like format('%%%s', has_req_suffix)
    );

    base_single_col_name text = left(
        foreign_columns[1],
        0-req_suffix_len
    );
    base_name text = graphql.type_name(foreign_entity, 'Node');
begin
    return
        coalesce(
            -- comment directive override
            foreign_name_override,
            graphql.lowercase_first_letter(
                case is_single_col_ending_id
                    when true then (
                        case
                            when is_inflection_on then graphql.to_camel_case(base_single_col_name)
                            else base_single_col_name
                        end
                    )
                    else base_name
                end
            )
        );
end;
$$;




create or replace function graphql.field_name_for_function(func regproc)
    returns text
    stable
    language sql
as $$
    select
        coalesce(
            graphql.comment_directive_name(func),
            case graphql.comment_directive_inflect_names(current_schema::regnamespace)
                when true then graphql.to_camel_case(ltrim(graphql.to_function_name(func), '_'))
                else ltrim(graphql.to_function_name(func), '_')
            end
        )
$$;


create or replace function graphql.field_name(rec graphql._field)
    returns text
    immutable
    language sql
as $$
    with base(name) as (
        select graphql.type_name(rec.entity, 'Node')
    )
    select
        case
            when rec.meta_kind = 'Constant' then rec.constant_name
            when rec.meta_kind in ('Column', 'OrderBy.Column', 'Filter.Column') then graphql.field_name_for_column(rec.entity, rec.column_name)
            when rec.meta_kind = 'Function' then graphql.field_name_for_function(rec.func)
            when rec.meta_kind = 'Query.collection' then graphql.field_name_for_query_collection(rec.entity)
            when rec.meta_kind = 'Mutation.insert' then format('insertInto%sCollection', base.name)
            when rec.meta_kind = 'Mutation.update' then format('update%sCollection', base.name)
            when rec.meta_kind = 'Mutation.delete' then format('deleteFrom%sCollection', base.name)
            when rec.meta_kind = 'Relationship.toMany' then graphql.field_name_for_to_many(rec.foreign_entity, rec.foreign_name_override)
            when rec.meta_kind = 'Relationship.toOne' then graphql.field_name_for_to_one(rec.foreign_entity, rec.foreign_name_override, rec.foreign_columns)
            when rec.constant_name is not null then rec.constant_name
            else graphql.exception(format('could not determine field name, %s', $1))
        end
    from
        base
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

    insert into graphql._field(parent_type_id, type_id, meta_kind, constant_name, is_not_null, is_array, is_array_not_null, is_hidden_from_schema, description)
    values
        (graphql.type_id('Query'), graphql.type_id('Datetime'), 'Query.heartbeat', 'heartbeat', true,  false, null, false, 'UTC Datetime from server');

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
                    ('Constant', edge.id, node.id,                     'node',       false, false, null::boolean, null::text, null::text, null::text[], null::text[], false),
                    ('Constant', edge.id, graphql.type_id('String'),   'cursor',     true,  false, null, null, null, null, null, false),
                    ('Constant', conn.id, edge.id,                     'edges',      true,  true,  true, null, null, null, null, false),
                    ('Constant', conn.id, graphql.type_id('PageInfo'::graphql.meta_kind), 'pageInfo',   true,  false, null, null, null, null, null, false),
                    ('Query.collection', graphql.type_id('Query'::graphql.meta_kind), conn.id, null, false, false, null,
                        format('A pagable collection of type `%s`', graphql.type_name(conn.entity, 'Node')), null, null, null, false)
            ) fs(field_meta_kind, parent_type_id, type_id, constant_name, is_not_null, is_array, is_array_not_null, description, column_name, foreign_columns, local_columns, is_hidden_from_schema)
        where
            conn.meta_kind = 'Connection'
            and edge.meta_kind = 'Edge'
            and node.meta_kind = 'Node';

    -- Connection.totalCount (opt in)
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, constant_name, is_not_null, is_array, description)
        select
            'Constant'::graphql.field_meta_kind,
            conn.entity,
            conn.id parent_type_id,
            graphql.type_id('Int') type_id,
            'totalCount',
            true as is_not_null,
            false as is_array,
            'The total number of records matching the `filter` criteria'
        from
            graphql.type conn
        where
            conn.meta_kind = 'Connection'
            and graphql.comment_directive_totalCount_enabled(conn.entity);

    -- Object.__typename
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, constant_name, is_not_null, is_array, is_hidden_from_schema)
        select
            '__Typename'::graphql.field_meta_kind,
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
            es.is_not_null and es.is_array as is_array_not_null,
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
            gt.meta_kind = 'Node'
            and not es.column_type in ('json', 'jsonb')
            and not es.is_composite;

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
            graphql.is_array(pp.prorettype::regtype) as is_array,
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
            gt.meta_kind = 'OrderBy'
            and not ec.column_type in ('json', 'jsonb')
            and not ec.is_composite;


    -- IntFilter {eq: ... neq: ... gt: ... gte: ... lt: ... lte: ... }
    insert into graphql._field(parent_type_id, type_id, constant_name, is_not_null, is_array, description)
        select
            gt.id as parent_type_id,
            gt.graphql_type_id type_id,
            ops.constant_name as constant_name,
            false,
            false,
            null::text as description
        from
            graphql.type gt -- IntFilter
            join (
                values
                    ('eq'),
                    ('lt'),
                    ('lte'),
                    ('neq'),
                    ('gte'),
                    ('gt')
            ) ops(constant_name)
                on true
        where
            gt.meta_kind = 'FilterType'
            and (
                gt.graphql_type_id not in (graphql.type_id('UUID'), graphql.type_id('JSON'))
                or ops.constant_name in ('eq', 'neq')
            );


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
            gt.meta_kind = 'FilterEntity'
            and not ec.is_array -- disallow arrays
            and not ec.column_type in ('json', 'jsonb')
            and not ec.is_composite; -- disallow composite


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
                    ('Mutation.insert', node.id, false, false, false, format('Adds one or more `%s` records to the collection', node.name))
            ) fs(field_meta_kind, type_id, is_not_null, is_array, is_array_not_null, description)
        where
            node.meta_kind = 'InsertNodeResponse';

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
            x.constant_name as constant_name,
            true as is_not_null,
            true as is_array,
            true as is_array_not_null,
            true as is_arg,
            f.id parent_arg_field_id,
            null as description
        from
            graphql.type t
            inner join graphql._field f
                on t.id = f.type_id
                and f.meta_kind = 'Mutation.insert'
            inner join graphql.type tt
                on t.entity = tt.entity
                and tt.meta_kind = 'InsertNode',
            lateral (
                values
                    ('ObjectsArg'::graphql.field_meta_kind, 'objects')
            ) x(meta_kind, constant_name);

    -- Mutation.insertAccount(object: {<column> })
    insert into graphql._field(meta_kind, entity, parent_type_id, type_id, is_not_null, is_array, is_array_not_null, is_arg, parent_arg_field_id, description, column_name, column_type, column_attribute_num, is_hidden_from_schema)
        select
            'Column' as meta_kind,
            gf.entity,
            gf.type_id parent_type_id,
            graphql.type_id(ec.column_type) as type_id,
            false as is_not_null,
            ec.is_array as is_array,
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
            gf.meta_kind = 'ObjectsArg'
            and not ec.is_generated -- skip generated columns
            and not ec.is_serial -- skip (big)serial columns
            and not ec.column_type in ('json', 'jsonb')
            and not ec.is_array -- disallow arrays
            and not ec.is_composite; -- disallow arrays


    -- AccountUpdateResponse.affectedCount
    -- AccountUpdateResponse.records
    -- AccountDeleteResponse.affectedCount
    -- AccountDeleteResponse.records
    -- AccountInsertResponse.affectedCount
    -- AccountInsertResponse.records
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
        t.meta_kind in ('DeleteNodeResponse', 'UpdateNodeResponse', 'InsertNodeResponse');


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
            ec.is_array,
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
            and not ec.is_serial -- skip (big)serial columns
            and not ec.column_type in ('json', 'jsonb')
            and not ec.is_array -- disallow arrays
            and not ec.is_composite; -- disallow composite

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
            when f.meta_kind = 'Mutation.insert' then (
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
            when f_arg_parent.meta_kind = 'ObjectsArg' then pg_catalog.has_column_privilege(
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
create or replace function graphql.arg_index(arg_name text, variable_definitions jsonb)
    returns int
    immutable
    strict
    language sql
as $$
    select
        ar.idx
    from
        jsonb_array_elements(variable_definitions) with ordinality ar(elem, idx)
    where
        graphql.name_literal(elem -> 'variable') = $1
$$;
create or replace function graphql.get_arg_by_name(name text, arguments jsonb)
    returns jsonb
    immutable
    strict
    language sql
as $$
    select
        ar.elem
    from
        jsonb_array_elements(arguments) ar(elem)
    where
        graphql.name_literal(elem) = $1
$$;
create or replace function graphql.arg_clause(name text, arguments jsonb, variable_definitions jsonb, entity regclass, default_value text = null)
    returns text
    immutable
    language plpgsql
as $$
declare
    arg jsonb = graphql.get_arg_by_name(name, graphql.jsonb_coalesce(arguments, '[]'));

    res text;

    cast_to regtype = case
        when name in ('first', 'last', 'atMost') then 'int'
        else 'text'
    end;

    var_ix int;
    var_name text;

begin
    if arg is null then
        return default_value;

    elsif graphql.is_variable(arg -> 'value') then

        -- variable name (if its a variable)
        var_name = graphql.name_literal(arg -> 'value');
        -- variable index (if its a variable)
        var_ix   = graphql.arg_index(var_name, variable_definitions);

        if var_ix is null then
            perform graphql.exception(format("unknown variable %s", var_name));
        end if;

        return format(
            '$%s::%s',
            var_ix,
            cast_to
        );

    -- Non-special literal
    else
        return
            format(
                '%L::%s',
                graphql.value_literal(arg),
                cast_to
            );
    end if;
end
$$;
create or replace function graphql.join_clause(local_columns text[], local_alias_name text, parent_columns text[], parent_alias_name text)
    returns text
    language sql
    immutable
    as
$$
    select string_agg(quote_ident(local_alias_name) || '.' || quote_ident(x) || ' = ' || quote_ident(parent_alias_name) || '.' || quote_ident(y), ' and ')
    from
        unnest(local_columns) with ordinality local_(x, ix),
        unnest(parent_columns) with ordinality parent_(y, iy)
    where
        ix = iy
$$;
create or replace function graphql.primary_key_clause(entity regclass, alias_name text)
    returns text
    language sql
    immutable
    as
$$
    select '(' || string_agg(quote_ident(alias_name) || '.' || quote_ident(x), ',') ||')'
    from unnest(graphql.primary_key_columns(entity)) pk(x)
$$;
create or replace function graphql.order_by_clause(
    alias_name text,
    column_orders graphql.column_order_w_type[]
)
    returns text
    language sql
    immutable
    as
$$
    select
        string_agg(
            format(
                '%I.%I %s %s',
                alias_name,
                (co).column_name,
                (co).direction::text,
                case
                    when (co).nulls_first then 'nulls first'
                    else 'nulls last'
                end
            ),
            ', '
        )
    from
        unnest(column_orders) co
$$;
create or replace function graphql.order_by_enum_to_clause(order_by_enum_val text)
    returns text
    language sql
    immutable
    as
$$
    select
        case order_by_enum_val
            when 'AscNullsFirst' then 'asc nulls first'
            when 'AscNullsLast' then 'asc nulls last'
            when 'DescNullsFirst' then 'desc nulls first'
            when 'DescNullsLast' then 'desc nulls last'
            else graphql.exception(format('Invalid value for ordering "%s"', coalesce(order_by_enum_val, 'null')))
        end
$$;
create or replace function graphql.to_column_orders(
    order_by_arg jsonb, -- Ex: [{"id": "AscNullsLast"}, {"name": "DescNullsFirst"}]
    entity regclass,
    variables jsonb default '{}'
)
    returns graphql.column_order_w_type[]
    language plpgsql
    immutable
    as
$$
declare
    pkey_ordering graphql.column_order_w_type[] = array_agg(
            (column_name, 'asc', false, y.column_type)::graphql.column_order_w_type
        )
        from
            unnest(graphql.primary_key_columns(entity)) with ordinality x(column_name, ix)
            join unnest(graphql.primary_key_types(entity)) with ordinality y(column_type, ix)
                on x.ix = y.ix;
begin

    -- No order by clause was specified
    if order_by_arg is null then
        return pkey_ordering;
    end if;

    return array_agg(
        (
            case
                when f.column_name is null then graphql.exception(
                    'Invalid list entry field name for order clause'
                )
                when f.column_name is not null then f.column_name
                else graphql.exception_unknown_field(x.key_, t.name)
            end,
            case when x.val_ like 'Asc%' then 'asc' else 'desc' end, -- asc or desc
            case when x.val_ like '%First' then true else false end, -- nulls_first?
            f.column_type
        )::graphql.column_order_w_type
    ) || pkey_ordering
    from
        jsonb_array_elements(order_by_arg) jae(obj),
        lateral (
            select
                case jsonb_typeof(jae.obj)
                    when 'object' then ''
                    else graphql.exception('Invalid order clause')
                end
        ) _validate_elem_is_object, -- unused
        lateral (
            select
                jet.key_,
                case
                    when jet.val_ in (
                        'AscNullsFirst',
                        'AscNullsLast',
                        'DescNullsFirst',
                        'DescNullsLast'
                    ) then jet.val_
                    else graphql.exception('Invalid order clause')
                end as val_
            from
                jsonb_each_text( jae.obj )  jet(key_, val_)
        ) x
        join graphql.type t
            on t.entity = $2
            and t.meta_kind = 'Node'
        left join graphql.field f
            on t.name = f.parent_type
            and f.name = x.key_;
end;
$$;
create type graphql.comparison_op as enum ('=', '<', '<=', '<>', '>=', '>');
create or replace function graphql.text_to_comparison_op(text)
    returns graphql.comparison_op
    language sql
    immutable
    as
$$
    select
        case $1
            when 'eq' then '='
            when 'lt' then '<'
            when 'lte' then '<='
            when 'neq' then '<>'
            when 'gte' then '>='
            when 'gt' then '>'
            else graphql.exception('Invalid comaprison operator')
        end::graphql.comparison_op
$$;
create or replace function graphql.where_clause(
    filter_arg jsonb,
    entity regclass,
    alias_name text,
    variables jsonb default '{}',
    variable_definitions jsonb default '{}'
)
    returns text
    language plpgsql
    immutable
    as
$$
declare
    clause_arr text[] = '{}';
    variable_name text;
    variable_ix int;
    variable_value jsonb;
    variable_part jsonb;

    sel jsonb;
    ix smallint;

    field_name text;
    column_name text;
    column_type regtype;

    field_value_obj jsonb;
    op_name text;
    field_value text;

    format_str text;

    -- Collect allowed comparison columns
    column_fields graphql.field[] = array_agg(f)
        from
            graphql.type t
            left join graphql.field f
                on t.name = f.parent_type
        where
            t.entity = $2
            and t.meta_kind = 'Node'
            and f.column_name is not null;
begin


    -- No filter specified
    if filter_arg is null then
        return 'true';


    elsif (filter_arg -> 'value' ->> 'kind') not in ('ObjectValue', 'Variable') then
        return graphql.exception('Invalid filter argument');

    -- Disallow variable order by clause because it is incompatible with prepared statements
    elsif (filter_arg -> 'value' ->> 'kind') = 'Variable' then
        -- Variable is <Table>Filter
        -- "{"id": {"eq": 1}, ...}"

        variable_name = graphql.name_literal(filter_arg -> 'value');

        variable_ix = graphql.arg_index(
            -- name of argument
            variable_name,
            variable_definitions
        );
        field_value = format('$%s', variable_ix);

        -- "{"id": {"eq": 1}}"
        variable_value = variables -> variable_name;

        if jsonb_typeof(variable_value) <> 'object' then
            return graphql.exception('Invalid filter argument');
        end if;

        for field_name, column_name, column_type, variable_part in
            select
                f.name,
                f.column_name,
                f.column_type,
                je.v -- {"eq": 1}
            from
                jsonb_each(variable_value) je(k, v)
                left join unnest(column_fields) f
                    on je.k = f.name
            loop

            -- Sanity checks
            if column_name is null or jsonb_typeof(variable_part) <> 'object' then
                -- Attempting to filter on field that does not exist
                return graphql.exception('Invalid filter field');
            end if;

            op_name = k from jsonb_object_keys(variable_part) x(k) limit 1;

            clause_arr = clause_arr || format(
                '%I.%I %s (%s::jsonb -> '
                    || format('%L ->> %L', field_name, op_name)
                    || ')::%s',
                alias_name,
                column_name,
                graphql.text_to_comparison_op(op_name),
                field_value,
                column_type
            );

        end loop;



    elsif (filter_arg -> 'value' ->> 'kind') = 'ObjectValue' then

        for sel, ix in
            select
                sel_, ix_
            from
                jsonb_array_elements( filter_arg -> 'value' -> 'fields') with ordinality oba(sel_, ix_)
            loop

            -- Must populate in every loop
            format_str = null;
            field_value = null;
            field_name = graphql.name_literal(sel);

            select
                into column_name, column_type
                f.column_name, f.column_type
            from
                unnest(column_fields) f
            where
                f.name = field_name;

            if column_name is null then
                -- Attempting to filter on field that does not exist
                return graphql.exception('Invalid filter field');
            end if;


            if graphql.is_variable(sel -> 'value') then
                -- Variable is <Type>Filter
                -- variables:= '{"ifilt": {"eq": 3}}'

                -- perform graphql.exception(sel ->> 'value');
                -- {"kind": "Variable", "name": {"kind": "Name", "value": "ifilt"}}"

                -- variable name
                -- variables -> (sel -> 'value' -> 'name' ->> 'value')


                -- variables:= '{"ifilt": {"eq": 3}}'
                variable_name = (sel -> 'value' -> 'name' ->> 'value');
                variable_ix = graphql.arg_index(
                    -- name of argument
                    variable_name,
                    variable_definitions
                );
                variable_value = variables -> variable_name;


                -- Sanity checks: '{"eq": 3}'
                if jsonb_typeof(variable_value) <> 'object' then
                    return graphql.exception('Invalid filter variable value');

                elsif (select count(1) <> 1 from jsonb_object_keys(variable_value)) then
                    return graphql.exception('Invalid filter variable value');

                end if;

                -- "eq"
                op_name = k from jsonb_object_keys(variable_value) x(k) limit 1;
                field_value = format('$%s', variable_ix);

                select
                    '%I.%I %s (%s::jsonb ->> ' || format('%L', op_name) || ')::%s'
                from
                    jsonb_each(variable_value)
                limit
                    1
                into format_str;

            elsif sel -> 'value' ->> 'kind' <> 'ObjectValue' then
                return graphql.exception('Invalid filter');

            else
                    /* {
                        "kind": "ObjectValue",
                        "fields": [
                            {
                                "kind": "ObjectField",
                                "name": {"kind": "Name", "value": "eq"},
                                "value": {"kind": "IntValue", "value": "2"}
                            }
                        ]
                    } */

                    field_value_obj = sel -> 'value' -> 'fields' -> 0;

                    if field_value_obj ->> 'kind' <> 'ObjectField' then
                        return graphql.exception('Invalid filter clause-2');

                    elsif (field_value_obj -> 'value' ->> 'kind') = 'Variable' then
                        format_str = '%I.%I %s %s::%s';
                        field_value = format(
                            '$%s',
                            graphql.arg_index(
                                -- name of argument
                                (field_value_obj -> 'value' -> 'name' ->> 'value'),
                                variable_definitions
                            )
                        );

                    else
                        format_str = '%I.%I %s %L::%s';
                        field_value = graphql.value_literal(field_value_obj);

                    end if;

                    -- "eq"
                    op_name = graphql.name_literal(field_value_obj);
            end if;

            clause_arr = clause_arr || format(
                format_str,
                alias_name,
                column_name,
                graphql.text_to_comparison_op(op_name),
                field_value,
                column_type
            );

        end loop;
    end if;

    return array_to_string(clause_arr, ' and ');
end;
$$;
create or replace function graphql.build_connection_query(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language plpgsql
as $$
declare
    block_name text = graphql.slug();
    entity regclass = t.entity
        from
            graphql.field f
            join graphql.type t
                on f.type_ = t.name
        where
            f.name = graphql.name_literal(ast)
            and f.parent_type = $4;

    ent alias for entity;

    arguments jsonb = graphql.jsonb_coalesce((ast -> 'arguments'), '[]');

    field_row graphql.field = f from graphql.field f where f.name = graphql.name_literal(ast) and f.parent_type = $4;
    first_ text = graphql.arg_clause(
        'first',
        arguments,
        variable_definitions,
        entity
    );
    last_ text = graphql.arg_clause('last',   arguments, variable_definitions, entity);

    -- If before or after is provided as a variable, and the value of the variable
    -- is explicitly null, we must treat it as though the value were not provided
    cursor_arg_ast jsonb = coalesce(
        graphql.get_arg_by_name('before', graphql.jsonb_coalesce(arguments, '[]')),
        graphql.get_arg_by_name('after', graphql.jsonb_coalesce(arguments, '[]'))
    );
    cursor_literal text = graphql.value_literal(cursor_arg_ast);
    cursor_var_name text = case graphql.is_variable(
            coalesce(cursor_arg_ast,'{}'::jsonb) -> 'value'
        )
        when true then graphql.name_literal(cursor_arg_ast -> 'value')
        else null
    end;
    cursor_var_ix int = graphql.arg_index(cursor_var_name, variable_definitions);

    -- ast
    before_ast jsonb = graphql.get_arg_by_name('before', arguments);
    after_ast jsonb = graphql.get_arg_by_name('after',  arguments);

    -- ordering is part of the cache key, so it is safe to extract it from
    -- variables or arguments
    -- Ex: [{"id": "AscNullsLast"}, {"name": "DescNullsFirst"}]
    order_by_arg jsonb = graphql.arg_coerce_list(
        graphql.arg_to_jsonb(
            graphql.get_arg_by_name('orderBy',  arguments),
            variables
        )
    );
    column_orders graphql.column_order_w_type[] = graphql.to_column_orders(
        order_by_arg,
        entity,
        variables
    );

    filter_arg jsonb = graphql.get_arg_by_name('filter',  arguments);

    total_count_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "totalCount"}'
    );

    __typename_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "__typename"}'
    );

    page_info_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "pageInfo"}'
    );

    edges_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "edges"}'
    );

    cursor_ast jsonb = jsonb_path_query_first(
        edges_ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "cursor"}'
    );

    node_ast jsonb = jsonb_path_query_first(
        edges_ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "node"}'
    );

    __typename_clause text;
    total_count_clause text;
    page_info_clause text;
    node_clause text;
    edges_clause text;

    result text;
begin
    if first_ is not null and last_ is not null then
        perform graphql.exception('only one of "first" and "last" may be provided');
    elsif before_ast is not null and after_ast is not null then
        perform graphql.exception('only one of "before" and "after" may be provided');
    elsif first_ is not null and before_ast is not null then
        perform graphql.exception('"first" may only be used with "after"');
    elsif last_ is not null and after_ast is not null then
        perform graphql.exception('"last" may only be used with "before"');
    end if;

    __typename_clause = format(
        '%L, %L',
        graphql.alias_or_name_literal(__typename_ast),
        field_row.type_
    ) where __typename_ast is not null;

    total_count_clause = format(
        '%L, coalesce(min(%I.%I), 0)',
        graphql.alias_or_name_literal(total_count_ast),
        block_name,
        '__total_count'
    ) where total_count_ast is not null;

    page_info_clause = case
        when page_info_ast is null then null
        else (
            select
                format(
                '%L, jsonb_build_object(%s)',
                graphql.alias_or_name_literal(page_info_ast),
                string_agg(
                    format(
                        '%L, %s',
                        graphql.alias_or_name_literal(pi.sel),
                        case graphql.name_literal(pi.sel)
                            when '__typename' then format('%L', pit.name)
                            when 'startCursor' then format('graphql.first(%I.__cursor order by %I.__page_row_num asc )', block_name, block_name)
                            when 'endCursor' then format('graphql.first(%I.__cursor order by %I.__page_row_num desc)', block_name, block_name)
                            when 'hasNextPage' then format(
                                'coalesce(bool_and(%I.__has_next_page), false)',
                                block_name
                            )
                            when 'hasPreviousPage' then format(
                                'coalesce(bool_and(%s), false)',
                                case
                                    when first_ is not null and after_ast is not null then 'true'
                                    when last_ is not null and before_ast is not null then 'true'
                                    else 'false'
                                end
                            )
                            else graphql.exception_unknown_field(graphql.name_literal(pi.sel), 'PageInfo')
                        end
                    ),
                    ','
                )
            )
        from
            jsonb_array_elements(page_info_ast -> 'selectionSet' -> 'selections') pi(sel)
            join graphql.type pit
                on true
        where
            pit.meta_kind = 'PageInfo'
        )
    end;


    node_clause = case
        when node_ast is null then null
        else (
            select
                format(
                    'jsonb_build_object(%s)',
                    string_agg(
                        format(
                            '%L, %s',
                            graphql.alias_or_name_literal(n.sel),
                            case
                                when gf_s.name = '__typename' then format('%L', gt.name)
                                when gf_s.column_name is not null and gf_s.column_type = 'bigint'::regtype then format(
                                    '(%I.%I)::text',
                                    block_name,
                                    gf_s.column_name
                                )
                                when gf_s.column_name is not null then format('%I.%I', block_name, gf_s.column_name)
                                when gf_s.local_columns is not null and gf_s.meta_kind = 'Relationship.toOne' then
                                    graphql.build_node_query(
                                        ast := n.sel,
                                        variable_definitions := variable_definitions,
                                        variables := variables,
                                        parent_type := gt.name,
                                        parent_block_name := block_name
                                    )
                                when gf_s.local_columns is not null and gf_s.meta_kind = 'Relationship.toMany' then
                                    graphql.build_connection_query(
                                        ast := n.sel,
                                        variable_definitions := variable_definitions,
                                        variables := variables,
                                        parent_type := gt.name,
                                        parent_block_name := block_name
                                    )
                                when gf_s.meta_kind = 'Function' then format('%I.%s', block_name, gf_s.func)
                                else graphql.exception_unknown_field(graphql.name_literal(n.sel), gt.name)
                            end
                        ),
                        ','
                    )
                )
                from
                    jsonb_array_elements(node_ast -> 'selectionSet' -> 'selections') n(sel) -- node selection
                    join graphql.type gt -- return type of node
                        on true
                    left join graphql.field gf_s -- node selections
                        on gt.name = gf_s.parent_type
                        and graphql.name_literal(n.sel) = gf_s.name
                where
                    gt.meta_kind = 'Node'
                    and gt.entity = ent
                    and not coalesce(gf_s.is_arg, false)
        )
    end;

    edges_clause = case
        when edges_ast is null then null
        else (
            select
                format(
                    '%L, coalesce(jsonb_agg(jsonb_build_object(%s)), jsonb_build_array())',
                    graphql.alias_or_name_literal(edges_ast),
                    string_agg(
                        format(
                            '%L, %s',
                            graphql.alias_or_name_literal(ec.sel),
                            case graphql.name_literal(ec.sel)
                                when 'cursor' then format('%I.%I', block_name, '__cursor')
                                when '__typename' then format('%L', gf_e.type_)
                                when 'node' then node_clause
                                else graphql.exception_unknown_field(graphql.name_literal(ec.sel), gf_e.type_)
                            end
                        ),
                        E',\n'
                    )
                )
                from
                    jsonb_array_elements(edges_ast -> 'selectionSet' -> 'selections') ec(sel)
                    join graphql.field gf_e -- edge field
                        on gf_e.parent_type = field_row.type_
                        and gf_e.name = 'edges'
        )
    end;

    -- Error out on invalid top level selections
    perform case
                when gf.name is not null then ''
                else graphql.exception_unknown_field(graphql.name_literal(root.sel), field_row.type_)
            end
        from
            jsonb_array_elements((ast -> 'selectionSet' -> 'selections')) root(sel)
            left join graphql.field gf
                on gf.parent_type = field_row.type_
                and gf.name = graphql.name_literal(root.sel);

    select
        format('
    (
        with xyz_tot as (
            select
                count(1) as __total_count
            from
                %s as %I
            where
                %s
                -- join clause
                and %s
                -- where clause
                and %s
        ),
        -- might contain 1 extra row
        xyz_maybe_extra as (
            select
                %s::text as __cursor,
                row_number() over () as __page_row_num_for_page_size,
                %s -- all requested columns
            from
                %s as %I
            where
                true
                --pagination_clause
                and ((%s is null) or (%s))
                -- join clause
                and %s
                -- where clause
                and %s
            order by
                %s
            limit
                least(%s, 30) + 1
        ),
        xyz as (
            select
                *,
                max(%I.__page_row_num_for_page_size) over () > least(%s, 30) as __has_next_page,
                row_number() over () as __page_row_num
            from
                xyz_maybe_extra as %I
            order by
                %s
            limit
                least(%s, 30)
        )
        select
            jsonb_build_object(%s)
        from
        (
            select
                *
            from
                xyz,
                xyz_tot
            order by
                %s
        ) as %I
    )
    ',
            -- total from
            entity,
            block_name,
            -- total count only computed if requested
            case
                when total_count_ast is null then 'false'
                else 'true'
            end,
            -- total join clause
            coalesce(graphql.join_clause(field_row.local_columns, block_name, field_row.foreign_columns, parent_block_name), 'true'),
            -- total where
            graphql.where_clause(filter_arg, entity, block_name, variables, variable_definitions),
            -- __cursor
            format(
                'graphql.encode(%s)',
                graphql.to_cursor_clause(
                    block_name,
                    column_orders
                )
            ),
            -- enumerate columns
            (
                select
                    coalesce(
                        string_agg(
                            case f.meta_kind
                                when 'Column' then format('%I.%I', block_name, column_name)
                                when 'Function' then format('%s(%I) as %s', f.func, block_name, f.func)
                                else graphql.exception('Unexpected meta_kind in select')
                            end,
                            ', '
                        )
                    )
                from
                    graphql.field f
                    join graphql.type t
                        on f.parent_type = t.name
                where
                    f.meta_kind in ('Column', 'Function') --(f.column_name is not null or f.func is not null)
                    and t.entity = ent
                    and t.meta_kind = 'Node'
            ),
            -- from
            entity,
            block_name,
            -- pagination
            case
                -- no variable or literal. do not restrict
                when cursor_var_ix is null and cursor_literal is null then 'null'
                when cursor_literal is not null then '1'
                else format('$%s', cursor_var_ix)
            end,
            graphql.cursor_where_clause(
                block_name := block_name,
                column_orders := case
                    when last_ is not null then graphql.reverse(column_orders)
                    else column_orders
                end,
                cursor_ := cursor_literal,
                cursor_var_ix := cursor_var_ix
            ),
            -- join
            coalesce(graphql.join_clause(field_row.local_columns, block_name, field_row.foreign_columns, parent_block_name), 'true'),
            -- where
            graphql.where_clause(filter_arg, entity, block_name, variables, variable_definitions),
            -- order
            graphql.order_by_clause(
                block_name,
                case
                    when last_ is not null then graphql.reverse(column_orders)
                    else column_orders
                end
            ),
            -- limit
            coalesce(first_, last_, '30'),
            -- has_next_page block namex
            block_name,
            -- xyz_has_next_page limit
            coalesce(first_, last_, '30'),
            -- xyz
            block_name,
            graphql.order_by_clause(
                block_name,
                case
                    when last_ is not null then graphql.reverse(column_orders)
                    else column_orders
                end
            ),
            coalesce(first_, last_, '30'),
            -- JSON selects
            concat_ws(', ', total_count_clause, page_info_clause, __typename_clause, edges_clause),
            -- final order by
            graphql.order_by_clause('xyz', column_orders),
            -- block name
            block_name
        )
        into result;

    return result;
end;
$$;
create or replace function graphql.build_delete(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language plpgsql
as $$
declare
    result text;

    block_name text = graphql.slug();

    field_rec graphql.field = f
        from
            graphql.field f
        where
            f.name = graphql.name_literal(ast) and f.meta_kind = 'Mutation.delete';

    arg_at_most graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'AtMostArg';
    at_most_clause text = graphql.arg_clause(
        'atMost',
        (ast -> 'arguments'),
        variable_definitions,
        field_rec.entity,
        arg_at_most.default_value
    );

    filter_arg jsonb = graphql.get_arg_by_name('filter',  graphql.jsonb_coalesce((ast -> 'arguments'), '[]'));
    where_clause text = graphql.where_clause(filter_arg, field_rec.entity, block_name, variables, variable_definitions);

    returning_clause text;
begin

    returning_clause = (
        select
            format(
                'jsonb_build_object( %s )',
                string_agg(
                    case
                        when top_fields.name = '__typename' then format(
                            '%L, %L',
                            graphql.alias_or_name_literal(top.sel),
                            field_rec.type_
                        )
                        when top_fields.name = 'affectedCount' then format(
                            '%L, %s',
                            graphql.alias_or_name_literal(top.sel),
                            'count(1)'
                        )
                        when top_fields.name = 'records' then (
                            select
                                format(
                                    '%L, coalesce(jsonb_agg(jsonb_build_object( %s )), jsonb_build_array())',
                                    graphql.alias_or_name_literal(top.sel),
                                    string_agg(
                                        format(
                                            '%L, %s',
                                            graphql.alias_or_name_literal(x.sel),
                                            case
                                                when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                                                when nf.meta_kind = 'Function' then format('%s(%I)', nf.func, block_name)
                                                when nf.name = '__typename' then format('%L', top_fields.type_)
                                                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                                                    ast := x.sel,
                                                    variable_definitions := variable_definitions,
                                                    variables := variables,
                                                    parent_type := top_fields.type_,
                                                    parent_block_name := block_name
                                                )
                                                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                                                    ast := x.sel,
                                                    variable_definitions := variable_definitions,
                                                    variables := variables,
                                                    parent_type := top_fields.type_,
                                                    parent_block_name := block_name
                                                )
                                                else graphql.exception_unknown_field(graphql.name_literal(x.sel), field_rec.type_)
                                            end
                                        ),
                                        ','
                                    )
                                )
                            from
                                lateral jsonb_array_elements(top.sel -> 'selectionSet' -> 'selections') x(sel)
                                left join graphql.field nf
                                    on top_fields.type_ = nf.parent_type
                                    and graphql.name_literal(x.sel) = nf.name
                            where
                                graphql.name_literal(top.sel) = 'records'
                        )
                        else graphql.exception_unknown_field(graphql.name_literal(top.sel), field_rec.type_)
                    end,
                    ', '
                )
            )
        from
            jsonb_array_elements(ast -> 'selectionSet' -> 'selections') top(sel)
            left join graphql.field top_fields
                on field_rec.type_ = top_fields.parent_type
                and graphql.name_literal(top.sel) = top_fields.name
    );


    result = format(
        'with deleted as (
            delete from %s as %I
            where %s
            returning *
        ),
        total(total_count) as (
            select
                count(*)
            from
                deleted
        ),
        req(res) as (
            select
                %s
            from
                deleted as %I
        ),
        wrapper(res) as (
            select
                case
                    when total.total_count > %s then graphql.exception($a$delete impacts too many records$a$)::jsonb
                    else req.res
                end
            from
                total
                left join req
                    on true
            limit 1
        )
        select
            res
        from
            wrapper;',
        field_rec.entity,
        block_name,
        where_clause,
        coalesce(returning_clause, 'null'),
        block_name,
        at_most_clause
    );

    return result;
end;
$$;
create or replace function graphql.build_heartbeat_query(
    ast jsonb
)
    returns text
    language sql
as $$
    select format('select to_jsonb( now() at time zone %L );', 'utc');
$$;
create or replace function graphql.build_insert(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null
)
    returns text
    language plpgsql
as $$
declare
    field_rec graphql.field = field
        from graphql.field
        where
            meta_kind = 'Mutation.insert'
            and name = graphql.name_literal(ast);

    entity regclass = field_rec.entity;

    arg_object graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'ObjectsArg';
    allowed_columns graphql.field[] = array_agg(field) from graphql.field where parent_arg_field_id = arg_object.id and meta_kind = 'Column';

    object_arg jsonb = graphql.get_arg_by_name(arg_object.name, graphql.jsonb_coalesce(ast -> 'arguments', '[]'));

    block_name text = graphql.slug();
    column_clause text;
    values_clause text;
    returning_clause text;
    result text;

    values_var jsonb; -- value for `objects` from variables
    values_all_field_keys text[]; -- all field keys referenced in values_var
begin
    if object_arg is null then
       perform graphql.exception_required_argument('objects');
    end if;

    if graphql.is_variable(object_arg -> 'value') then
        values_var = variables -> graphql.name_literal(object_arg -> 'value');

    elsif (object_arg -> 'value' ->> 'kind') = 'ListValue' then
        -- Literals and Column Variables
        select
            jsonb_agg(
                case
                    when graphql.is_variable(row_.ast) then (
                        case
                            when jsonb_typeof(variables -> (graphql.name_literal(row_.ast))) <> 'object' then graphql.exception('Invalid value for objects record')::jsonb
                            else variables -> (graphql.name_literal(row_.ast))
                        end
                    )
                    when row_.ast ->> 'kind' = 'ObjectValue' then (
                        select
                            jsonb_object_agg(
                                graphql.name_literal(rec_vals.ast),
                                case
                                    when graphql.is_variable(rec_vals.ast -> 'value') then (variables ->> (graphql.name_literal(rec_vals.ast -> 'value')))
                                    else graphql.value_literal(rec_vals.ast)
                                end
                            )
                        from
                            jsonb_array_elements(row_.ast -> 'fields') rec_vals(ast)
                    )
                    else graphql.exception('Invalid value for objects record')::jsonb
                end
            )
        from
            jsonb_array_elements(object_arg -> 'value' -> 'values') row_(ast) -- one per "record" of data
        into
            values_var;

        -- Handle empty list input
        values_var = coalesce(values_var, jsonb_build_array());
    else
        perform graphql.exception('Invalid value for objects record')::jsonb;
    end if;

    -- Confirm values is a list
    if not jsonb_typeof(values_var) = 'array' then
        perform graphql.exception('Invalid value for objects. Expected list');
    end if;

    -- Confirm each element of values is an object
    perform (
        select
            string_agg(
                case jsonb_typeof(x.elem)
                    when 'object' then 'irrelevant'
                    else graphql.exception('Invalid value for objects. Expected list of objects')
                end,
                ','
            )
        from
            jsonb_array_elements(values_var) x(elem)
    );

    if not jsonb_array_length(values_var) > 0 then
        perform graphql.exception('At least one record must be provided to objects');
    end if;

    values_all_field_keys = (
        select
            array_agg(distinct y.key_)
        from
            jsonb_array_elements(values_var) x(elem),
            jsonb_each(x.elem) y(key_, val_)
    );

    -- Confirm all keys are valid field names
    select
        string_agg(
            case
                when ac.name is not null then format('%I', ac.column_name)
                else graphql.exception_unknown_field(vfk.field_name)
            end,
            ','
            order by vfk.field_name asc
        )
    from
        unnest(values_all_field_keys) vfk(field_name)
        left join unnest(allowed_columns) ac
            on vfk.field_name = ac.name
    into
        column_clause;

    -- At this point all field keys are known safe
    with value_rows(r) as (
        select
            format(
                format(
                    '(%s)',
                    string_agg(
                        format(
                            '%s',
                            case
                                when row_col.field_val is null then 'default'
                                else format('%L', row_col.field_val)
                            end
                        ),
                        ', '
                        order by vfk.field_name asc
                    )
                )
            )
        from
            jsonb_array_elements(values_var) with ordinality row_(elem, ix),
            unnest(values_all_field_keys) vfk(field_name)
            left join jsonb_each_text(row_.elem) row_col(field_name, field_val)
                on vfk.field_name = row_col.field_name
        group by
            row_.ix
    )
    select
        string_agg(r, ', ')
    from
        value_rows
    into
        values_clause;

    returning_clause = (
        select
            format(
                'jsonb_build_object( %s )',
                string_agg(
                    case
                        when top_fields.name = '__typename' then format(
                            '%L, %L',
                            graphql.alias_or_name_literal(top.sel),
                            field_rec.type_
                        )
                        when top_fields.name = 'affectedCount' then format(
                            '%L, %s',
                            graphql.alias_or_name_literal(top.sel),
                            'count(1)'
                        )
                        when top_fields.name = 'records' then (
                            select
                                format(
                                    '%L, coalesce(jsonb_agg(jsonb_build_object( %s )), jsonb_build_array())',
                                    graphql.alias_or_name_literal(top.sel),
                                    string_agg(
                                        format(
                                            '%L, %s',
                                            graphql.alias_or_name_literal(x.sel),
                                            case
                                                when nf.column_name is not null and nf.column_type = 'bigint'::regtype then format('(%I.%I)::text', block_name, nf.column_name)
                                                when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                                                when nf.meta_kind = 'Function' then format('%s(%I)', nf.func, block_name)
                                                when nf.name = '__typename' then format('%L', top_fields.type_)
                                                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                                                    ast := x.sel,
                                                    variable_definitions := variable_definitions,
                                                    variables := variables,
                                                    parent_type := top_fields.type_,
                                                    parent_block_name := block_name
                                                )
                                                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                                                    ast := x.sel,
                                                    variable_definitions := variable_definitions,
                                                    variables := variables,
                                                    parent_type := top_fields.type_,
                                                    parent_block_name := block_name
                                                )
                                                else graphql.exception_unknown_field(graphql.name_literal(x.sel))
                                            end
                                        ),
                                        ','
                                    )
                                )
                            from
                                lateral jsonb_array_elements(top.sel -> 'selectionSet' -> 'selections') x(sel)
                                left join graphql.field nf
                                    on top_fields.type_ = nf.parent_type
                                    and graphql.name_literal(x.sel) = nf.name
                            where
                                graphql.name_literal(top.sel) = 'records'
                        )
                        else graphql.exception_unknown_field(graphql.name_literal(top.sel), field_rec.type_)
                    end,
                    ', '
                )
            )
        from
            jsonb_array_elements(ast -> 'selectionSet' -> 'selections') top(sel)
            left join graphql.field top_fields
                on field_rec.type_ = top_fields.parent_type
                and graphql.name_literal(top.sel) = top_fields.name
    );

    result = format(
        'with affected as (
            insert into %s(%s)
            values %s
            returning *
        )
        select
            %s
        from
            affected as %I;
        ',
        field_rec.entity,
        column_clause,
        values_clause,
        coalesce(returning_clause, 'null'),
        block_name
    );

    return result;
end;
$$;
create or replace function graphql.build_node_query(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language sql
    stable
as $$
    select
        format('
            (
                select
                    jsonb_build_object(%s)
                from
                    %s as %I
                where
                    true
                    -- join clause
                    and %s
                    -- filter clause
                    and %s = %s
                limit 1
            )',
            string_agg(
                format('%L, %s',
                    graphql.alias_or_name_literal(x.sel),
                    case
                        when nf.column_name is not null and nf.column_type = 'bigint'::regtype then format('(%I.%I)::text', block_name, nf.column_name)
                        when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                        when nf.meta_kind = 'Function' then format('%s(%I)', nf.func, block_name)
                        when nf.name = '__typename' then format('%L', (c.type_).name)
                        when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                            ast := x.sel,
                            variable_definitions := variable_definitions,
                            variables := variables,
                            parent_type := (c.field).type_,
                            parent_block_name := block_name
                        )
                        when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                            ast := x.sel,
                            variable_definitions := variable_definitions,
                            variables := variables,
                            parent_type := (c.field).type_,
                            parent_block_name := block_name
                        )
                        else graphql.exception_unknown_field(graphql.name_literal(x.sel), (c.field).type_)
                    end
                ),
                ', '
            ),
            (c.type_).entity,
            c.block_name,
            coalesce(graphql.join_clause((c.field).local_columns, block_name, (c.field).foreign_columns, parent_block_name), 'true'),
            'true',
            'true'
    )
    from
        (
            -- Define constants
            select
                graphql.slug(),
                gf,
                gt
            from
                graphql.field gf
                join graphql.type gt
                    on gt.name = gf.type_
            where
                gf.name = graphql.name_literal(ast)
                and gf.parent_type = $4
        ) c(block_name, field, type_)
        join jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
            on true
        left join graphql.field nf
            on nf.parent_type = (c.field).type_
            and graphql.name_literal(x.sel) = nf.name
    where
        (c.field).name = graphql.name_literal(ast)
        and $4 = (c.field).parent_type
    group by
        c.block_name,
        c.field,
        c.type_
$$;
create or replace function graphql.build_update(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language plpgsql
as $$
declare
    result text;

    block_name text = graphql.slug();

    field_rec graphql.field = f
        from
            graphql.field f
        where
            f.name = graphql.name_literal(ast) and f.meta_kind = 'Mutation.update';

    filter_arg jsonb = graphql.get_arg_by_name('filter',  graphql.jsonb_coalesce((ast -> 'arguments'), '[]'));
    where_clause text = graphql.where_clause(filter_arg, field_rec.entity, block_name, variables, variable_definitions);
    returning_clause text;

    arg_at_most graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'AtMostArg';
    at_most_clause text = graphql.arg_clause(
        'atMost',
        (ast -> 'arguments'),
        variable_definitions,
        field_rec.entity,
        arg_at_most.default_value
    );

    arg_set graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'UpdateSetArg';
    allowed_columns graphql.field[] = array_agg(field) from graphql.field where parent_arg_field_id = arg_set.id and meta_kind = 'Column';
    set_arg_ix int = graphql.arg_index(arg_set.name, variable_definitions);
    set_arg jsonb = graphql.get_arg_by_name(arg_set.name, graphql.jsonb_coalesce(ast -> 'arguments', '[]'));
    set_clause text;
begin

    if set_arg is null then
        perform graphql.exception('missing argument "set"');
    end if;

    if graphql.is_variable(set_arg -> 'value') then
        -- `set` is variable
        select
            string_agg(
                format(
                    '%I = ($%s::jsonb ->> %L)::%s',
                    case
                        when ac.column_name is not null then ac.column_name
                        else graphql.exception_unknown_field(x.key_, ac.type_)
                    end,
                    graphql.arg_index(
                        graphql.name_literal(set_arg -> 'value'),
                        variable_definitions
                    ),
                    x.key_,
                    ac.column_type
                ),
                ', '
            )
        from
            jsonb_each(variables -> graphql.name_literal(set_arg -> 'value')) x(key_, val)
            left join unnest(allowed_columns) ac
                on x.key_ = ac.name
        into
            set_clause;

    else
        -- Literals and Column Variables
        select
            string_agg(
                case
                    when graphql.is_variable(val -> 'value') then format(
                        '%I = ($%s)::%s',
                        case
                            when ac.meta_kind = 'Column' then ac.column_name
                            else graphql.exception_unknown_field(graphql.name_literal(val), field_rec.type_)
                        end,
                        graphql.arg_index(
                            (val -> 'value' -> 'name' ->> 'value'),
                            variable_definitions
                        ),
                        ac.column_type

                    )
                    else format(
                        '%I = (%L)::%s',
                        case
                            when ac.meta_kind = 'Column' then ac.column_name
                            else graphql.exception_unknown_field(graphql.name_literal(val), field_rec.type_)
                        end,
                        graphql.value_literal(val),
                        ac.column_type
                    )
                end,
                ', '
            )
        from
            jsonb_array_elements(set_arg -> 'value' -> 'fields') arg_cols(val)
            left join unnest(allowed_columns) ac
                on graphql.name_literal(arg_cols.val) = ac.name
        into
            set_clause;

    end if;

    returning_clause = (
        select
            format(
                'jsonb_build_object( %s )',
                string_agg(
                    case
                        when top_fields.name = '__typename' then format(
                            '%L, %L',
                            graphql.alias_or_name_literal(top.sel),
                            field_rec.type_
                        )
                        when top_fields.name = 'affectedCount' then format(
                            '%L, %s',
                            graphql.alias_or_name_literal(top.sel),
                            'count(1)'
                        )
                        when top_fields.name = 'records' then (
                            select
                                format(
                                    '%L, coalesce(jsonb_agg(jsonb_build_object( %s )), jsonb_build_array())',
                                    graphql.alias_or_name_literal(top.sel),
                                    string_agg(
                                        format(
                                            '%L, %s',
                                            graphql.alias_or_name_literal(x.sel),
                                            case
                                                when nf.column_name is not null and nf.column_type = 'bigint'::regtype then format('(%I.%I)::text', block_name, nf.column_name)
                                                when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                                                when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                                                when nf.name = '__typename' then format('%L', top_fields.type_)
                                                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                                                    ast := x.sel,
                                                    variable_definitions := variable_definitions,
                                                    variables := variables,
                                                    parent_type := top_fields.type_,
                                                    parent_block_name := block_name
                                                )
                                                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                                                    ast := x.sel,
                                                    variable_definitions := variable_definitions,
                                                    variables := variables,
                                                    parent_type := top_fields.type_,
                                                    parent_block_name := block_name
                                                )
                                                else graphql.exception_unknown_field(graphql.name_literal(x.sel), top_fields.type_)
                                            end
                                        ),
                                        ','
                                    )
                                )
                            from
                                lateral jsonb_array_elements(top.sel -> 'selectionSet' -> 'selections') x(sel)
                                left join graphql.field nf
                                    on top_fields.type_ = nf.parent_type
                                    and graphql.name_literal(x.sel) = nf.name
                            where
                                graphql.name_literal(top.sel) = 'records'
                        )
                        else graphql.exception_unknown_field(graphql.name_literal(top.sel), field_rec.type_)
                    end,
                    ', '
                )
            )
        from
            jsonb_array_elements(ast -> 'selectionSet' -> 'selections') top(sel)
            left join graphql.field top_fields
                on field_rec.type_ = top_fields.parent_type
                and graphql.name_literal(top.sel) = top_fields.name
    );

    result = format(
        'with updated as (
            update %s as %I
            set %s
            where %s
            returning *
        ),
        total(total_count) as (
            select
                count(*)
            from
                updated
        ),
        req(res) as (
            select
                %s
            from
                updated as %I
        ),
        wrapper(res) as (
            select
                case
                    when total.total_count > %s then graphql.exception($a$update impacts too many records$a$)::jsonb
                    else req.res
                end
            from
                total
                left join req
                    on true
            limit 1
        )
        select
            res
        from
            wrapper;',
        field_rec.entity,
        block_name,
        set_clause,
        where_clause,
        coalesce(returning_clause, 'null'),
        block_name,
        at_most_clause
    );

    return result;
end;
$$;
create or replace function graphql."resolve_enumValues"(type_ text, ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    -- todo: remove overselection
    select
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'name', value::text,
                    'description', null::text,
                    'isDeprecated', false,
                    'deprecationReason', null
                )
            ),
            jsonb_build_array()
        )
    from
        graphql.enum_value ev where ev.type_ = $1;
$$;
create or replace function graphql.resolve_field(field text, parent_type text, parent_arg_field_id integer, ast jsonb)
    returns jsonb
    stable
    language plpgsql
as $$
declare
    field_rec graphql.field;
    field_recs graphql.field[];
begin
    field_recs = array_agg(gf)
        from
            graphql.field gf
        where
            gf.name = $1
            and gf.parent_type = $2
            and (
                (gf.parent_arg_field_id is null and $3 is null)
                or gf.parent_arg_field_id = $3
            )
            limit 1;

    field_rec = field_recs[1];

    return
        coalesce(
            jsonb_object_agg(
                fa.field_alias,
                case
                    when selection_name = 'name' then to_jsonb(field_rec.name)
                    when selection_name = 'description' then to_jsonb(field_rec.description)
                    when selection_name = 'isDeprecated' then to_jsonb(false) -- todo
                    when selection_name = 'deprecationReason' then to_jsonb(null::text) -- todo
                    when selection_name = 'type' then graphql."resolve___Type"(
                                                            field_rec.type_,
                                                            x.sel,
                                                            field_rec.is_array_not_null,
                                                            field_rec.is_array,
                                                            field_rec.is_not_null
                    )
                    when selection_name = 'args' then (
                        select
                            coalesce(
                                jsonb_agg(
                                    graphql.resolve_field(
                                        ga.name,
                                        field_rec.type_,
                                        field_rec.id,
                                        x.sel
                                    )
                                    order by
                                        ga.column_attribute_num,
                                        case ga.name
                                            when 'first' then 80
                                            when 'last' then 81
                                            when 'before' then 82
                                            when 'after' then 83
                                            when 'after' then 83
                                            when 'filter' then 95
                                            when 'orderBy' then 96
                                            when 'atMost' then 97
                                            else 0
                                        end,
                                        ga.name
                                ),
                                '[]'
                            )
                        from
                            graphql.field ga
                        where
                            ga.parent_arg_field_id = field_rec.id
                            and not ga.is_hidden_from_schema
                            and ga.is_arg
                            and ga.parent_type = field_rec.type_
                    )
                    -- INPUT_OBJECT types only
                    when selection_name = 'defaultValue' then to_jsonb(field_rec.default_value)
                    else graphql.exception_unknown_field(selection_name, field_rec.type_)::jsonb
                end
            ),
            'null'::jsonb
        )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel),
        lateral (
            select
                graphql.alias_or_name_literal(x.sel) field_alias,
                graphql.name_literal(x.sel) as selection_name
        ) fa;
end;
$$;
create or replace function graphql."resolve___Schema"(
    ast jsonb,
    variable_definitions jsonb = '[]'
)
    returns jsonb
    stable
    language plpgsql
    as $$
declare
    node_fields jsonb = jsonb_path_query(ast, '$.selectionSet.selections');
    node_field jsonb;
    node_field_rec graphql.field;
    agg jsonb = '{}';
begin
    --field_rec = "field" from graphql.field where parent_type = '__Schema' and name = field_name;

    for node_field in select * from jsonb_array_elements(node_fields) loop
        node_field_rec = "field" from graphql.field where parent_type = '__Schema' and name = graphql.name_literal(node_field);

        if graphql.name_literal(node_field) = 'description' then
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), node_field_rec.description);
        elsif node_field_rec.type_ = '__Directive' then
            -- TODO
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), '[]'::jsonb);

        elsif node_field_rec.name = 'queryType' then
           -- agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), graphql.resolve_query_type(node_field));
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), graphql."resolve___Type"('Query', node_field));

        elsif node_field_rec.name = 'mutationType' then
            agg = agg || jsonb_build_object(
                graphql.alias_or_name_literal(node_field),
                case exists(select 1 from graphql.field where parent_type = 'Mutation' and not is_hidden_from_schema)
                    when true then graphql."resolve___Type"('Mutation', node_field)
                    else null
                end
            );

        elsif node_field_rec.name = 'subscriptionType' then
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), null);

        elsif node_field_rec.name = 'types' then
            agg = agg || (
                with uq as (
                    select
                        distinct gt.name
                    from
                        graphql.type gt
                        -- Filter out object types with no fields
                        join (
                            select
                                distinct parent_type
                            from
                                graphql.field
                            where
                                not is_hidden_from_schema
                                -- scheam.queryType is non null so we must include it
                                -- even when its empty. a client exception will be thrown
                                -- if not fields exist
                                or parent_type = 'Query'
                            ) gf
                            on gt.name = gf.parent_type
                            or gt.type_kind not in ('OBJECT', 'INPUT_OBJECT')
                )
                select
                    jsonb_build_object(
                        graphql.alias_or_name_literal(node_field),
                        jsonb_agg(graphql."resolve___Type"(uq.name, node_field) order by uq.name)
                    )
                from uq
            );

        elsif node_field_rec.type_ = '__Type' and not node_field_rec.is_array then
            agg = agg || graphql."resolve___Type"(
                node_field_rec.type_,
                node_field,
                node_field_rec.is_array_not_null,
                node_field_rec.is_array,
                node_field_rec.is_not_null
            );

        else
            raise 'Invalid field for type __Schema: "%"', graphql.name_literal(node_field);
        end if;
    end loop;

    return jsonb_build_object(graphql.alias_or_name_literal(ast), agg);
end
$$;
create or replace function graphql."resolve___Type"(
    type_ text,
    ast jsonb,
    is_array_not_null bool = false,
    is_array bool = false,
    is_not_null bool = false
)
    returns jsonb
    stable
    language plpgsql
as $$
declare
begin
       return
        coalesce(
            jsonb_object_agg(
                fa.field_alias,
                case
                    when selection_name = 'name' and not has_modifiers then to_jsonb(gt.name::text)
                    when selection_name = 'description' and not has_modifiers then to_jsonb(gt.description::text)
                    when selection_name = 'specifiedByURL' and not has_modifiers then to_jsonb(null::text)
                    when selection_name = 'kind' then (
                        case
                            when is_array_not_null then to_jsonb('NON_NULL'::text)
                            when is_array then to_jsonb('LIST'::text)
                            when is_not_null then to_jsonb('NON_NULL'::text)
                            else to_jsonb(gt.type_kind::text)
                        end
                    )
                    when selection_name = 'fields' and not has_modifiers then (
                        select
                            jsonb_agg(
                                graphql.resolve_field(
                                    f.name,
                                    f.parent_type,
                                    null,
                                    x.sel
                                )
                                order by
                                    f.column_attribute_num,
                                    f.name
                        )
                        from
                            graphql.field f
                        where
                            f.parent_type = gt.name
                            and not f.is_hidden_from_schema
                            and gt.type_kind = 'OBJECT'
                            and not f.is_arg
                            and (
                                -- heartbeat is not visible unless the query type is empty
                                gt.meta_kind <> 'Query'
                                or f.meta_kind <> 'Query.heartbeat'
                                or not exists(
                                    select 1
                                    from graphql.field fin
                                    where
                                        fin.parent_type = gt.name -- 'Query'
                                        and not fin.is_hidden_from_schema
                                        and fin.meta_kind <> 'Query.heartbeat'
                                    limit 1
                                )
                            )
                    )
                    when selection_name = 'interfaces' and not has_modifiers then (
                        case
                            -- Scalars get null, objects get an empty list. This is a poor implementation
                            -- when gt.meta_kind not in ('Interface', 'BUILTIN', 'CURSOR') then '[]'::jsonb
                            when gt.type_kind = 'SCALAR' then to_jsonb(null::text)
                            when gt.type_kind = 'INTERFACE' then to_jsonb(null::text)
                            when gt.meta_kind = 'Cursor' then to_jsonb(null::text)
                            else '[]'::jsonb
                        end
                    )
                    when selection_name = 'possibleTypes' and not has_modifiers then to_jsonb(null::text)
                    when selection_name = 'enumValues' then graphql."resolve_enumValues"(gt.name, x.sel)
                    when selection_name = 'inputFields' and not has_modifiers then (
                        select
                            jsonb_agg(
                                graphql.resolve_field(
                                    f.name,
                                    f.parent_type,
                                    f.parent_arg_field_id,
                                    x.sel
                                )
                                order by
                                    f.column_attribute_num,
                                    f.name
                            )
                        from
                            graphql.field f
                        where
                            f.parent_type = gt.name
                            and not f.is_hidden_from_schema
                            and gt.type_kind = 'INPUT_OBJECT'
                    )
                    when selection_name = 'ofType' then (
                        case
                            -- NON_NULL(LIST(...))
                            when is_array_not_null is true then graphql."resolve___Type"(type_, x.sel, is_array_not_null := false, is_array := is_array, is_not_null := is_not_null)
                            -- LIST(...)
                            when is_array then graphql."resolve___Type"(type_, x.sel, is_array_not_null := false, is_array := false, is_not_null := is_not_null)
                            -- NON_NULL(...)
                            when is_not_null then graphql."resolve___Type"(type_, x.sel, is_array_not_null := false, is_array := false, is_not_null := false)
                            -- TYPE
                            else null
                        end
                    )
                    else null
                end
            ),
            'null'::jsonb
        )
    from
        graphql.type gt
        join jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
            on true,
        lateral (
            select
                graphql.alias_or_name_literal(x.sel) field_alias,
                graphql.name_literal(x.sel) as selection_name
        ) fa,
        lateral (
            select (coalesce(is_array_not_null, false) or is_array or is_not_null) as has_modifiers
        ) hm
    where
        gt.name = type_;
end;
$$;
create or replace function graphql.cache_key(
    role regrole,
    schemas text[],
    schema_version int,
    ast jsonb,
    variables jsonb
)
    returns text
    language sql
    immutable
as $$
    select
        -- Different roles may have different levels of access
        md5(
            $1::text
            || $2::text
            || $3::text
            -- Parsed query hash
            || ast::text
            || graphql.cache_key_variable_component(variables)
        )
$$;
create or replace function graphql.cache_key_variable_component(variables jsonb = '{}')
    returns text
    language sql
    immutable
as $$
/*
Some GraphQL variables are not compatible with prepared statement
For example, the order by clause can be passed via a variable, but
SQL prepared statements can dynamically sort by column name or direction
based on a parameter.

This function returns a string that can be included in the cache key for
a query to ensure separate prepared statements for each e.g. column order + direction
and filtered column names

While false positives are possible, the cost of false positives is low
*/
    with doc as (
        select
            *
        from
            graphql.jsonb_unnest_recursive_with_jsonpath(variables)
    ),
    general_structure as (
        select
            jpath::text as x
        from
            doc
    ),
    order_clause as (
        select
            jpath::text || '=' || obj as x
        from
            doc
        where
            obj #>> '{}' in ('AscNullsFirst', 'AscNullsLast', 'DescNullsFirst', 'DescNullsLast')
    )
    select
        coalesce(string_agg(y.x, ',' order by y.x), '')
    from
        (
            select x from general_structure
            union all
            select x from order_clause
        ) y(x)
$$;
create table graphql.introspection_query_cache(
    cache_key text primary key, -- equivalent to prepared statement name
    response_data jsonb
);

create or replace function graphql.get_introspection_cache(cache_key text)
    returns jsonb
    security definer
    language sql
as $$
    select
        response_data
    from
        graphql.introspection_query_cache
    where
        cache_key = $1
    limit 1
$$;

create or replace function graphql.set_introspection_cache(cache_key text, response_data jsonb)
    returns void
    security definer
    language sql
as $$
    insert into
        graphql.introspection_query_cache(cache_key, response_data)
    values
        ($1, $2)
    on conflict (cache_key) do nothing;
$$;
create or replace function graphql.prepared_statement_create_clause(statement_name text, variable_definitions jsonb, query_ text)
    returns text
    immutable
    language sql
as $$
    -- Create Prepared Statement
    select format(
        'prepare %I %s as %s',
        statement_name,
        case jsonb_array_length(variable_definitions)
            when 0 then ''
            else (select '(' || string_agg('text', ', ') || ')' from jsonb_array_elements(variable_definitions) jae(vd))
        end,
        query_
    )
$$;
create or replace function graphql.prepared_statement_execute_clause(statement_name text, variable_definitions jsonb, variables jsonb)
    returns text
    immutable
    language sql
as $$
   select
        case count(1)
            when 0 then format('execute %I', statement_name)
            else
                format(
                    'execute %I ( %s )',
                    statement_name,
                    string_agg(format('%L', coalesce(var.val, def ->> 'defaultValue')), ',' order by def_idx)
                )
        end
    from
        jsonb_array_elements(variable_definitions) with ordinality d(def, def_idx)
        left join jsonb_each_text(variables) var(key_, val)
            on graphql.name_literal(def -> 'variable') = var.key_
$$;
create or replace function graphql.prepared_statement_exists(statement_name text)
    returns boolean
    language sql
    stable
as $$
    select exists(select 1 from pg_prepared_statements where name = statement_name)
$$;
create or replace function graphql.argument_value_by_name(name text, ast jsonb)
    returns text
    immutable
    language sql
as $$
    select jsonb_path_query_first(ast, ('$.arguments[*] ? (@.name.value == "' || name ||'")')::jsonpath) -> 'value' ->> 'value';
$$;
create or replace function graphql.resolve(
    query text = null,
    variables jsonb = '{}',
    "operationName" text = null,
    extensions jsonb = null
)
    returns jsonb
    volatile
    language plpgsql
as $$
declare
    ---------------------
    -- Always required --
    ---------------------
    parsed graphql.parse_result = graphql.parse(coalesce(query, ''));
    ast jsonb = parsed.ast;


    n_operation_defs int = jsonb_array_length(
        jsonb_path_query_array(
            ast,
            '$.definitions[*] ? (@.kind == "OperationDefinition")'
        )
    );

    -- AST for the operation part of the def, not e.g. fragments
    ast_operation jsonb = case
        when "operationName" is not null then jsonb_path_query_first(
            ast,
            '$.definitions[*] ? (@.kind == "OperationDefinition" && @.name.value == $op_name)',
            jsonb_build_object(
                'op_name',
                "operationName"
            )
        )
        when n_operation_defs = 1 then jsonb_path_query_first(
            ast,
            '$.definitions[*] ? (@.kind == "OperationDefinition")'
        )
        else null
    end;

    n_statements int = jsonb_array_length(ast_operation -> 'selectionSet' -> 'selections');

    variable_definitions jsonb = coalesce(graphql.variable_definitions_sort(ast_operation -> 'variableDefinitions'), '[]');

    -- Query or Mutation?
    operation graphql.meta_kind = (
        case (ast_operation ->> 'operation')
            when 'mutation' then 'Mutation'
            when 'query' then 'Query'
        end
    );

    prepared_statement_name text;

    q text;
    data_ jsonb;
    request_data jsonb;
    errors_ jsonb[] = case
        when parsed.error is not null then array[jsonb_build_object('message', parsed.error)]
        when ast_operation is null then array[jsonb_build_object('message', 'unknown operation')]
        else '{}'
    end;

    ---------------------
    -- If not in cache --
    ---------------------

    -- AST without location info ("loc" key)
    ast_statement jsonb;
    ast_locless jsonb;

    -- ast with fragments inlined
    fragment_definitions jsonb;
    ast_inlined jsonb;

    meta_kind graphql.meta_kind;
    field_meta_kind graphql.field_meta_kind;

    -- Exception stack
    error_message text;
begin


    if errors_ <> '{}' then
       -- If an error was encountered before execution begins, the data entry should not be present in the result.
       return jsonb_build_object(
        'errors', to_jsonb(errors_)
       );
    end if;

    -- Rebuild the schema cache if the SQL schema has changed
    perform graphql.rebuild_schema();

    fragment_definitions = graphql.ast_pass_strip_loc(
        jsonb_path_query_array(ast, '$.definitions[*] ? (@.kind == "FragmentDefinition")')
    );

    begin

        -- Build query if not in cache
        for statement_ix in 0..(n_statements - 1) loop

            ast_statement = (
                 ast_operation -> 'selectionSet' -> 'selections' -> statement_ix
            );

            prepared_statement_name = (
                case
                    when operation = 'Query' then graphql.cache_key(
                        current_user::regrole,
                        current_schemas(false),
                        graphql.get_built_schema_version(),
                        jsonb_build_object(
                            'statement', ast_statement,
                            'fragment_defs', fragment_definitions
                        ),
                        variables
                    )
                    -- If not a query (mutation) don't attempt to cache
                    else md5(format('%s%s%s',random(),random(),random()))
                end
            );

            if errors_ = '{}' and not graphql.prepared_statement_exists(prepared_statement_name) then

                    ast_locless = graphql.ast_pass_strip_loc(ast_statement);

                    -- Skip fragment inline when no fragments are present
                    ast_inlined = case
                        when fragment_definitions = '[]'::jsonb then ast_locless
                        else graphql.ast_pass_fragments(ast_locless, fragment_definitions)
                    end;

                    field_meta_kind = f.meta_kind
                        from
                            graphql.field f
                        where
                            f.parent_type = operation::text
                            and f.name = graphql.name_literal(ast_inlined);

                    if field_meta_kind is null then
                        perform graphql.exception_unknown_field(
                            graphql.name_literal(ast_inlined),
                            operation::text
                        );
                    end if;

                    q = case field_meta_kind
                        when 'Mutation.insert' then
                            graphql.build_insert(
                                ast := ast_inlined,
                                variable_definitions := variable_definitions,
                                variables := variables
                            )
                        when 'Mutation.delete' then
                            graphql.build_delete(
                                ast := ast_inlined,
                                variable_definitions := variable_definitions,
                                variables := variables
                            )
                        when 'Mutation.update' then
                            graphql.build_update(
                                ast := ast_inlined,
                                variable_definitions := variable_definitions,
                                variables := variables
                            )
                        when 'Query.collection' then
                                graphql.build_connection_query(
                                    ast := ast_inlined,
                                    variable_definitions := variable_definitions,
                                    variables := variables,
                                    parent_type :=  'Query',
                                    parent_block_name := null
                                )
                        when 'Query.heartbeat' then graphql.build_heartbeat_query(ast_inlined)
                        when '__Typename' then format(
                            $typename_stmt$ select to_jsonb(%L::text) $typename_stmt$,
                            (
                                select
                                    f.parent_type
                                from
                                    graphql.field f
                                where
                                    f.parent_type = operation::text
                                    and f.name = graphql.name_literal(ast_inlined)
                                limit 1
                            )
                        )
                    end;

                    if q is null and operation = 'Query' then

                        meta_kind = type_.meta_kind
                            from
                                graphql.field
                                join graphql.type type_
                                    on field.type_ = type_.name
                            where
                                field.parent_type = 'Query'
                                and field.name = graphql.name_literal(ast_inlined);

                        if meta_kind is null then
                            perform graphql.exception_unknown_field(
                                graphql.name_literal(ast_inlined),
                                'Query'
                            );
                        end if;


                        if graphql.get_introspection_cache(prepared_statement_name) is not null then
                            data_ = graphql.get_introspection_cache(prepared_statement_name);
                        else
                            data_ = case meta_kind
                                when '__Schema' then
                                    graphql."resolve___Schema"(
                                        ast := ast_inlined,
                                        variable_definitions := variable_definitions
                                    )
                                when '__Type' then
                                    jsonb_build_object(
                                        graphql.alias_or_name_literal(ast_statement),
                                        graphql."resolve___Type"(
                                            (
                                                select
                                                    name
                                                from
                                                    graphql.type type_
                                                where
                                                    name = graphql.argument_value_by_name('name', ast_inlined)
                                            ),
                                            ast_inlined
                                        )
                                    )
                                else null::jsonb
                            end;
                            perform graphql.set_introspection_cache(prepared_statement_name, data_);
                        end if;
                    end if;
            end if;

            if errors_ = '{}' and q is not null then
                execute graphql.prepared_statement_create_clause(prepared_statement_name, variable_definitions, q);
            end if;

            if errors_ = '{}' and data_ is null then
                -- Call prepared statement respecting passed values and variable definition defaults
                execute graphql.prepared_statement_execute_clause(prepared_statement_name, variable_definitions, variables) into data_;
                data_ = jsonb_build_object(
                    graphql.alias_or_name_literal(ast_statement),
                    data_
                );
            end if;

            -- Add data to final state
            request_data = case
                when request_data is null then data_
                else request_data || data_
            end;

            -- reset loop vars
            q = null;
            data_ = null;

        end loop;

    exception when others then
        get stacked diagnostics error_message = MESSAGE_TEXT;
        errors_ = errors_ || jsonb_build_object('message', error_message);
        -- Do no show partial or rolled back results
        request_data = null;
    end;


    return (
        -- If no errors were encountered during the requested operation, the errors entry should not be present in the result.
        jsonb_build_object('data', request_data)
        || case
           when errors_ <> '{}' then jsonb_build_object(
                'errors', to_jsonb(errors_),
                -- If an error was encountered during the execution that prevented a valid response, the data entry in the response should be null
                'data', null::text
            )
            else  '{}'
        end
    );
end
$$;
create or replace function graphql.variable_definitions_sort(variable_definitions jsonb)
    returns jsonb
    immutable
    language sql
as $$
  -- Deterministically sort variable definitions
  select
        jsonb_agg(jae.f order by jae.f -> 'variable' -> 'name' ->> 'value' asc)
    from
        jsonb_array_elements(
            case jsonb_typeof(variable_definitions)
                when 'array' then variable_definitions
                else to_jsonb('{}'::text[])
            end
        ) jae(f)
$$;
-- Is updated every time the schema changes
create sequence if not exists graphql.seq_schema_version as int cycle;

-- Tracks the most recently built schema version
-- Contains 1 row
create table graphql.schema_version(ver int primary key);
insert into graphql.schema_version(ver) values (nextval('graphql.seq_schema_version') - 1);

create or replace function graphql.get_built_schema_version()
    returns int
    security definer
    language sql
as $$
    select ver from graphql.schema_version limit 1;
$$;

create or replace function graphql.rebuild_schema()
    returns void
    security definer
    language plpgsql
as $$
declare
    cur_schema_version int = last_value from graphql.seq_schema_version;
    built_schema_version int = graphql.get_built_schema_version();
begin
    if built_schema_version <> cur_schema_version then
        -- Lock the row to avoid concurrent access
        built_schema_version = ver from graphql.schema_version for update;

        -- Recheck condition now that we have aquired a row lock to avoid racing & stacking requests
        if built_schema_version <> cur_schema_version then
            truncate table graphql._field;
            delete from graphql._type where true; -- satisfy safedelete
            refresh materialized view graphql.entity with data;
            refresh materialized view graphql.entity_column with data;
            refresh materialized view graphql.entity_unique_columns with data;
            refresh materialized view graphql.relationship with data;
            perform graphql.rebuild_types();
            perform graphql.rebuild_fields();
            truncate table graphql.introspection_query_cache;

            -- Update the stored schema version value
            update graphql.schema_version set ver = cur_schema_version where true; -- satisfy safedelete

        end if;
    end if;
end;
$$;

create or replace function graphql.rebuild_on_ddl()
    returns event_trigger
    language plpgsql
as $$
declare
    cmd record;
begin
    for cmd IN select * FROM pg_event_trigger_ddl_commands()
    loop
        if cmd.command_tag in (
            'CREATE SCHEMA',
            'ALTER SCHEMA',
            'CREATE TABLE',
            'CREATE TABLE AS',
            'SELECT INTO',
            'ALTER TABLE',
            'CREATE FOREIGN TABLE',
            'ALTER FOREIGN TABLE'
            'CREATE VIEW',
            'ALTER VIEW',
            'CREATE MATERIALIZED VIEW',
            'ALTER MATERIALIZED VIEW',
            'CREATE FUNCTION',
            'ALTER FUNCTION',
            'CREATE TRIGGER',
            'CREATE TYPE',
            'CREATE RULE',
            'GRANT',
            'REVOKE',
            'COMMENT'
        )
        and cmd.schema_name is distinct from 'pg_temp'
        then
            perform nextval('graphql.seq_schema_version');
        end if;
    end loop;
end;
$$;


create or replace function graphql.rebuild_on_drop()
    returns event_trigger
    language plpgsql
as $$
declare
    obj record;
begin
    for obj IN SELECT * FROM pg_event_trigger_dropped_objects()
        loop
            if obj.object_type IN (
                'schema',
                'table',
                'foreign table',
                'view',
                'materialized view',
                'function',
                'trigger',
                'type',
                'rule'
            )
            and obj.is_temporary IS false
            then
                perform nextval('graphql.seq_schema_version');
            end if;
    end loop;
end;
$$;

select graphql.rebuild_schema();


-- On DDL event, increment the schema version number
create event trigger graphql_watch_ddl
    on ddl_command_end
    execute procedure graphql.rebuild_on_ddl();

create event trigger graphql_watch_drop
    on sql_drop
    execute procedure graphql.rebuild_on_drop();
