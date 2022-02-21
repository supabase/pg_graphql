create schema if not exists graphql;
create or replace function graphql.array_first(arr anyarray)
    returns anyelement
    language sql
    immutable
as
$$
    -- First element of an array
    select arr[1];
$$;
create or replace function graphql.array_last(arr anyarray)
    returns anyelement
    language sql
    immutable
as
$$
    -- Last element of an array
    select arr[array_length(arr, 1)];
$$;
create or replace function graphql.sha1(text)
    returns text
    strict
    immutable
    language sql
as $$
    select encode(digest($1, 'sha1'), 'hex')
$$;
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
create function graphql.to_type_name(regtype)
    returns text
    language sql
    immutable
as
$$ select coalesce(nullif(split_part($1::text, '.', 2), ''), $1::text) $$;
create function graphql.to_function_name(regproc)
    returns text
    language sql
    immutable
as
$$ select coalesce(nullif(split_part($1::text, '.', 2), ''), $1::text) $$;
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
create or replace function graphql.exception_unknown_field(field_name text, type_name text)
    returns text
    language plpgsql
as $$
begin
    raise exception using errcode='22000', message=format('Unknown field %L on type %L', field_name, type_name);
end;
$$;
create or replace function graphql.cursor_clause_for_literal(cursor_ text)
    returns text
    language sql
    immutable
    as
$$
    -- SQL string
    -- Example:
    --        select graphql.cursor_clause_for_literal('WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd')
    --        row('public','account','2')
    -- Note:
    --         Type casts are not necessary because the values are visible to the planner allowing coercion
    select 'row(' || string_agg(quote_literal(x), ',') || ')'
    from jsonb_array_elements_text(convert_from(decode(cursor_, 'base64'), 'utf-8')::jsonb) y(x)
$$;
create or replace function graphql.cursor_clause_for_variable(entity regclass, variable_idx int)
    returns text
    language sql
    immutable
    strict
as $$
    -- SQL string to decode a cursor and convert it to a record for equality or pagination
    -- Example:
    --        select graphql.cursor_clause_for_variable('public.account', 1)
    --        row(graphql.cursor_decode($1)::text, graphql.cursor_decode($1)::text, graphql.cursor_decode($1)::integer)
    select
        'row(' || string_agg(format('(graphql.cursor_decode($%s) ->> %s)::%s', variable_idx, ctype.idx-1, ctype.val), ', ') || ')'
    from
        unnest(array['text'::regtype] || graphql.primary_key_types(entity)) with ordinality ctype(val, idx);
$$;
create or replace function graphql.cursor_decode(cursor_ text)
    returns jsonb
    language sql
    immutable
    strict
as $$
    -- Decodes a base64 encoded jsonb array of [schema_name, table_name, pkey_val1, pkey_val2, ...]
    -- Example:
    --        select graphql.cursor_decode('WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd')
    --        ["public", "account", 1]
    select convert_from(decode(cursor_, 'base64'), 'utf-8')::jsonb
$$;
create or replace function graphql.cursor_encode(contents jsonb)
    returns text
    language sql
    immutable
    strict
as $$
    -- Encodes a jsonb array of [schema_name, table_name, pkey_val1, pkey_val2, ...] to a base64 encoded string
    -- Example:
    --        select graphql.cursor_encode('["public", "account", 1]'::jsonb)
    --        'WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd'
    select encode(convert_to(contents::text, 'utf-8'), 'base64')
$$;
create or replace function graphql.cursor_encoded_clause(entity regclass, alias_name text)
    returns text
    language sql
    immutable
    as
$$
    -- SQL string returning encoded cursor for an aliased table
    -- Example:
    --        select graphql.cursor_encoded_clause('public.account', 'abcxyz')
    --        graphql.cursor_encode(jsonb_build_array('public', 'account', abcxyz.id))
    select
        'graphql.cursor_encode(jsonb_build_array('
        || format('%L::text,', quote_ident(entity::text))
        || string_agg(quote_ident(alias_name) || '.' || quote_ident(x), ',')
        ||'))'
    from unnest(graphql.primary_key_columns(entity)) pk(x)
$$;
create or replace function graphql.cursor_row_clause(entity regclass, alias_name text)
    returns text
    language sql
    immutable
    as
$$
    -- SQL string returning decoded cursor for an aliased table
    -- Example:
    --        select graphql.cursor_row_clause('public.account', 'abcxyz')
    --        row('public', 'account', abcxyz.id)
    select
        'row('
        || format('%L::text,', quote_ident(entity::text))
        || string_agg(quote_ident(alias_name) || '.' || quote_ident(x), ',')
        ||')'
    from unnest(graphql.primary_key_columns(entity)) pk(x)
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


create function graphql.comment_directive_name(regclass, column_name text)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1, column_name)) ->> 'name'
$$;


create function graphql.comment_directive_name(regclass)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1)) ->> 'name'
$$;


create function graphql.comment_directive_name(regtype)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1)) ->> 'name'
$$;

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


create function graphql.sql_type_is_array(regtype)
    returns boolean
    immutable
    language sql
as
$$
    select pg_catalog.format_type($1, null) like '%[]'
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
                    graphql.comment_directive_name(rec.entity),
                    case
                        -- when the name contains a capital do not attempt inflection
                        when graphql.to_table_name(rec.entity) <> lower(graphql.to_table_name(rec.entity)) then graphql.to_table_name(rec.entity)
                        else graphql.inflect_type_default(graphql.to_table_name(rec.entity))
                    end
                )
                else null
            end as base_type_name
    )
    select
        case
            when (rec).is_builtin then rec.meta_kind::text
            when rec.meta_kind='Node'         then base_type_name
            when rec.meta_kind='CreateNode'   then format('%sCreateInput',base_type_name)
            when rec.meta_kind='UpdateNode'   then format('%sUpdateInput',base_type_name)
            when rec.meta_kind='UpdateNodeResponse' then format('%sUpdateResponse',base_type_name)
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
                    when meta_kind = 'CreateNode'
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
    );
create materialized view graphql.entity as
    select
        oid::regclass as entity
    from
        pg_class
    where
        relkind = ANY (ARRAY['r', 'p'])
        and not relnamespace = ANY (ARRAY[
            'information_schema'::regnamespace,
            'pg_catalog'::regnamespace,
            'graphql'::regnamespace
        ]);


create view graphql.entity_column as
    select
        e.entity,
        pa.attname::text as column_name,
        pa.atttypid::regtype as column_type,
        graphql.sql_type_is_array(pa.atttypid::regtype) is_array,
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


create view graphql.entity_unique_columns as
    select distinct
        ec.entity,
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
        ec.entity;
create function graphql.sql_type_to_graphql_type(sql_type text)
    returns text
    language sql
as
$$
    -- SQL type from pg_catalog.format_type
    select
        case
            when sql_type like 'int%' then 'Int' -- unsafe for int8
            when sql_type like 'bool%' then 'Boolean'
            when sql_type like 'float%' then 'Float'
            when sql_type like 'numeric%' then 'Float' -- unsafe
            when sql_type = 'json' then 'JSON'
            when sql_type = 'jsonb' then 'JSON'
            when sql_type like 'json%' then 'JSON'
            when sql_type = 'uuid' then 'UUID'
            when sql_type = 'daterange' then 'String'
            when sql_type like 'date%' then 'DateTime'
            when sql_type like 'timestamp%' then 'DateTime'
            when sql_type like 'time%' then 'DateTime'
            --when sql_type = 'inet' then 'InternetAddress'
            --when sql_type = 'cidr' then 'InternetAddress'
            --when sql_type = 'macaddr' then 'MACAddress'
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
        graphql.type_id(
            graphql.sql_type_to_graphql_type(
                -- strip trailing [] for array types
                regexp_replace(
                    pg_catalog.format_type($1, null),
                    '\[\]$',
                    ''
                )
            )
        )
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
            ('DateTime', 'SCALAR', true, null),
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
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "DateTime"', graphql.type_id('DateTime')),
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
                    ('INPUT_OBJECT',              'CreateNode',              null,       ent.entity),
                    ('INPUT_OBJECT',              'UpdateNode',              null,       ent.entity),
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
create view graphql.relationship as
    with rels as materialized (
        select
            const.conname as constraint_name,
            const.oid as constraint_oid,
            e.entity as local_entity,
            array_agg(local_.attname::text order by l.col_ix asc) as local_columns,
            'MANY'::graphql.cardinality as local_cardinality,
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

    is_opaque boolean = name in ('before', 'after');

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

        if is_opaque then
            return graphql.cursor_clause_for_variable(
                entity,
                var_ix
            );

        else
            return format(
                '$%s::%s',
                var_ix,
                cast_to
            );
        end if;

    elsif is_opaque then
        return graphql.cursor_clause_for_literal(graphql.value_literal(arg));

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
    order_by_arg jsonb,
    entity regclass,
    alias_name text,
    reverse bool default false,
    variables jsonb default '{}'
)
    returns text
    language plpgsql
    immutable
    as
$$
declare
    claues text;
    variable_value jsonb;
begin
    -- No order by clause was specified
    if order_by_arg is null then
        return graphql.primary_key_clause(entity, alias_name) || case when reverse then ' desc' else ' asc' end;
        -- todo handle no primary key
    end if;

    if (order_by_arg -> 'value' ->> 'kind') = 'Variable' then

        -- Expect [{"fieldName", "DescNullsFirst"}]
        variable_value = variables -> (order_by_arg -> 'value' -> 'name' ->> 'value');

        if jsonb_typeof(variable_value) <> 'array' or jsonb_array_length(variable_value) = 0 then
            return graphql.exception('Invalid value for ordering variable');
        end if;

        -- name of the variable
        return string_agg(
            format(
                '%I.%I %s',
                alias_name,
                case
                    when f.column_name is null then graphql.exception('Invalid list entry field name for order clause')
                    when f.column_name is not null then f.column_name
                    else graphql.exception_unknown_field(x.key_, t.name)
                end,
                graphql.order_by_enum_to_clause(val_)
            ),
            ', '
        )
        from
            jsonb_array_elements(variable_value) jae(obj),
            lateral (
                select
                    jet.key_,
                    jet.val_
                from
                    jsonb_each_text( jae.obj )  jet(key_, val_)
            ) x
            join graphql.type t
                on t.entity = $2
                and t.meta_kind = 'Node'
            left join graphql.field f
                on t.name = f.parent_type
                and f.name = x.key_;


    elsif (order_by_arg -> 'value' ->> 'kind') = 'ListValue' then
        return (
            with obs as (
                select
                    *
                from
                    jsonb_array_elements( order_by_arg -> 'value' -> 'values') with ordinality oba(sel, ix)
            ),
            norm as (
                -- Literal
                select
                    ext.field_name,
                    ext.direction_val,
                    obs.ix,
                    case
                        when field_name is null then graphql.exception('Invalid order clause')
                        when direction_val is null then graphql.exception('Invalid order clause')
                        else null
                    end as errors
                from
                    obs,
                    lateral (
                        select
                            graphql.name_literal(sel -> 'fields' -> 0) field_name,
                            graphql.value_literal(sel -> 'fields' -> 0) direction_val
                    ) ext
                where
                    not graphql.is_variable(obs.sel)
                union all
                -- Variable
                select
                    v.field_name,
                    v.direction_val,
                    obs.ix,
                    case
                        when v.field_name is null then graphql.exception('Invalid order clause')
                        when v.direction_val is null then graphql.exception('Invalid order clause')
                        else null
                    end as errors
                from
                    obs,
                    lateral (
                        select
                            field_name,
                            direction_val
                        from
                            jsonb_each_text(
                                case jsonb_typeof(variables -> graphql.name_literal(obs.sel))
                                    when 'object' then variables -> graphql.name_literal(obs.sel)
                                    else graphql.exception('Invalid order clause')::jsonb
                                end
                            ) jv(field_name, direction_val)
                        ) v
                where
                    graphql.is_variable(obs.sel)
            )
            select
                string_agg(
                    format(
                        '%I.%I %s',
                        alias_name,
                        case
                            when f.column_name is not null then f.column_name
                            else graphql.exception('Invalid order clause')
                        end,
                        graphql.order_by_enum_to_clause(norm.direction_val)
                    ),
                    ', '
                    order by norm.ix asc
                )
            from
                norm
                join graphql.type t
                    on t.entity = $2
                    and t.meta_kind = 'Node'
                left join graphql.field f
                    on t.name = f.parent_type
                    and f.name = norm.field_name
        );

    else
        return graphql.exception('Invalid type for order clause');
    end if;
end;
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
create type graphql.comparison_op as enum ('=');
create or replace function graphql.text_to_comparison_op(text)
    returns graphql.comparison_op
    language sql
    immutable
    as
$$
    select
        case $1
            when 'eq' then '='
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
    result text;
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
    before_ text = graphql.arg_clause('before', arguments, variable_definitions, entity);
    after_ text = graphql.arg_clause('after',  arguments, variable_definitions, entity);

    order_by_arg jsonb = graphql.get_arg_by_name('orderBy',  arguments);
    filter_arg jsonb = graphql.get_arg_by_name('filter',  arguments);

begin
    with clauses as (
        select
            (
                array_remove(
                    array_agg(
                        case
                            when graphql.name_literal(root.sel) = 'totalCount' then
                                format(
                                    '%L, coalesce(min(%I.%I), 0)',
                                    graphql.alias_or_name_literal(root.sel),
                                    block_name,
                                    '__total_count'
                                )
                            else null::text
                        end
                    ),
                    null
                )
            )[1] as total_count_clause,
            (
                array_remove(
                    array_agg(
                        case
                            when graphql.name_literal(root.sel) = '__typename' then
                                format(
                                    '%L, %L',
                                    graphql.alias_or_name_literal(root.sel),
                                    field_row.type_
                                )
                            else null::text
                        end
                    ),
                    null
                )
            )[1] as typename_clause,
            (
                array_remove(
                    array_agg(
                        case
                            when graphql.name_literal(root.sel) = 'pageInfo' then
                                format(
                                    '%L, jsonb_build_object(%s)',
                                    graphql.alias_or_name_literal(root.sel),
                                    (
                                        select
                                            string_agg(
                                                format(
                                                    '%L, %s',
                                                    graphql.alias_or_name_literal(pi.sel),
                                                    case graphql.name_literal(pi.sel)
                                                        when '__typename' then (select quote_literal(name) from graphql.type where meta_kind = 'PageInfo')
                                                        when 'startCursor' then format('graphql.array_first(array_agg(%I.__cursor))', block_name)
                                                        when 'endCursor' then format('graphql.array_last(array_agg(%I.__cursor))', block_name)
                                                        when 'hasNextPage' then format(
                                                            'coalesce(graphql.array_last(array_agg(%I.__cursor)) <> graphql.array_first(array_agg(%I.__last_cursor)), false)',
                                                            block_name,
                                                            block_name
                                                        )
                                                        when 'hasPreviousPage' then format(
                                                            'coalesce(graphql.array_first(array_agg(%I.__cursor)) <> graphql.array_first(array_agg(%I.__first_cursor)), false)',
                                                            block_name,
                                                            block_name
                                                        )
                                                        else graphql.exception_unknown_field(graphql.name_literal(pi.sel), 'PageInfo')

                                                    end
                                                )
                                                , E','
                                            )
                                        from
                                            jsonb_array_elements(root.sel -> 'selectionSet' -> 'selections') pi(sel)
                                    )
                                )
                            else null::text
                        end
                    ),
                    null
                )
            )[1] as page_info_clause,


            (
                array_remove(
                    array_agg(
                        case
                            when graphql.name_literal(root.sel) = 'edges' then
                                format(
                                    '%L, coalesce(jsonb_agg(%s %s), jsonb_build_array())',
                                    graphql.alias_or_name_literal(root.sel),
                                    (
                                        select
                                            coalesce(
                                                string_agg(
                                                    case graphql.name_literal(ec.sel)
                                                        when 'cursor' then format('jsonb_build_object(%L, %I.%I)', graphql.alias_or_name_literal(ec.sel), block_name, '__cursor')
                                                        when '__typename' then format('jsonb_build_object(%L, %L)', graphql.alias_or_name_literal(ec.sel), gf_e.type_)
                                                        else graphql.exception_unknown_field(graphql.name_literal(ec.sel), gf_e.type_)
                                                    end,
                                                    '||'
                                                ),
                                                'jsonb_build_object()'
                                            )
                                        from
                                            jsonb_array_elements(root.sel -> 'selectionSet' -> 'selections') ec(sel)
                                            join graphql.field gf_e -- edge field
                                                on gf_e.parent_type = field_row.type_
                                                and gf_e.name = 'edges'
                                        where
                                            graphql.name_literal(root.sel) = 'edges'
                                            and graphql.name_literal(ec.sel) <> 'node'
                                    ),
                                    (
                                        select
                                            format(
                                                '|| jsonb_build_object(%L, jsonb_build_object(%s))',
                                                graphql.alias_or_name_literal(e.sel),
                                                    string_agg(
                                                        format(
                                                            '%L, %s',
                                                            graphql.alias_or_name_literal(n.sel),
                                                            case
                                                                when gf_s.name = '__typename' then quote_literal(gf_n.type_)
                                                                when gf_s.column_name is not null then format('%I.%I', block_name, gf_s.column_name)
                                                                when gf_s.local_columns is not null and gf_st.meta_kind = 'Node' then
                                                                    graphql.build_node_query(
                                                                        ast := n.sel,
                                                                        variable_definitions := variable_definitions,
                                                                        variables := variables,
                                                                        parent_type := gf_n.type_,
                                                                        parent_block_name := block_name
                                                                    )
                                                                when gf_s.local_columns is not null and gf_st.meta_kind = 'Connection' then
                                                                    graphql.build_connection_query(
                                                                        ast := n.sel,
                                                                        variable_definitions := variable_definitions,
                                                                        variables := variables,
                                                                        parent_type := gf_n.type_,
                                                                        parent_block_name := block_name
                                                                    )
                                                                when gf_s.meta_kind = 'Function' then format('%I.%I', block_name, gf_s.func)
                                                                else graphql.exception_unknown_field(graphql.name_literal(n.sel), gf_n.type_)
                                                            end
                                                        ),
                                                        E','
                                                    )
                                            )
                                        from
                                            jsonb_array_elements(root.sel -> 'selectionSet' -> 'selections') e(sel), -- node (0 or 1)
                                            lateral jsonb_array_elements(e.sel -> 'selectionSet' -> 'selections') n(sel) -- node selection
                                            join graphql.field gf_e -- edge field
                                                on field_row.type_ = gf_e.parent_type
                                                and gf_e.name = 'edges'
                                            join graphql.field gf_n -- node field
                                                on gf_e.type_ = gf_n.parent_type
                                                and gf_n.name = 'node'
                                            left join graphql.field gf_s -- node selections
                                                on gf_n.type_ = gf_s.parent_type
                                                and graphql.name_literal(n.sel) = gf_s.name
                                            left join graphql.type gf_st
                                                on gf_s.type_ = gf_st.name
                                        where
                                            graphql.name_literal(e.sel) = 'node'
                                        group by
                                            e.sel
                                )
                            )
                        else null::text
                    end
                ),
                null
            )
        )[1] as edges_clause,

        -- Error handling for unknown fields at top level
        (
            array_agg(
                case
                    when graphql.name_literal(root.sel) not in ('pageInfo', 'edges', 'totalCount', '__typename') then graphql.exception_unknown_field(graphql.name_literal(root.sel), field_row.type_)
                    else null::text
                end
            )
        ) as error_handler

        from
            jsonb_array_elements((ast -> 'selectionSet' -> 'selections')) root(sel)
    )
    select
        format('
    (
        with xyz as (
            select
                count(*) over () __total_count,
                first_value(%s) over (order by %s range between unbounded preceding and current row)::text as __first_cursor,
                last_value(%s) over (order by %s range between current row and unbounded following)::text as __last_cursor,
                %s::text as __cursor,
                %s -- all allowed columns
            from
                %s as %I
            where
                true
                --pagination_clause
                and %s %s %s
                -- join clause
                and %s
                -- where clause
                and %s
            order by
                %s
            limit %s
        )
        select
            -- total count
            jsonb_build_object(
            %s
            )
            -- page info
            || jsonb_build_object(
            %s
            )
            -- edges
            || jsonb_build_object(
            %s
            )
            -- __typename
            || jsonb_build_object(
            %s
            )
        from
        (
            select
                *
            from
                xyz
            order by
                %s
        ) as %s
    )',
            -- __first_cursor
            graphql.cursor_encoded_clause(entity, block_name),
            graphql.order_by_clause(order_by_arg, entity, block_name, false, variables),
            -- __last_cursor
            graphql.cursor_encoded_clause(entity, block_name),
            graphql.order_by_clause(order_by_arg, entity, block_name, false, variables),
            -- __cursor
            graphql.cursor_encoded_clause(entity, block_name),
            -- enumerate columns
            (
                select
                    coalesce(
                        string_agg(
                            case f.meta_kind
                                when 'Column' then format('%I.%I', block_name, column_name)
                                when 'Function' then format('%I(%I) as %I', f.func, block_name, f.func)
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
            case when coalesce(after_, before_) is null then 'true' else graphql.cursor_row_clause(entity, block_name) end,
            case when after_ is not null then '>' when before_ is not null then '<' else '=' end,
            case when coalesce(after_, before_) is null then 'true' else coalesce(after_, before_) end,
            -- join
            coalesce(graphql.join_clause(field_row.local_columns, block_name, field_row.foreign_columns, parent_block_name), 'true'),
            -- where
            graphql.where_clause(filter_arg, entity, block_name, variables, variable_definitions),
            -- order
            case
                when last_ is not null then graphql.order_by_clause(order_by_arg, entity, block_name, true, variables)
                else graphql.order_by_clause(order_by_arg, entity, block_name, false, variables)
            end,
            -- limit: max 20
            least(coalesce(first_, last_), '30'),
            -- JSON selects
            coalesce(clauses.total_count_clause, ''),
            coalesce(clauses.page_info_clause, ''),
            coalesce(clauses.edges_clause, ''),
            coalesce(clauses.typename_clause, ''),
            -- final order by
            graphql.order_by_clause(order_by_arg, entity, 'xyz', false, variables),
            -- block name
            quote_ident(block_name)
        )
        from clauses
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
                            top_fields.type_
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
                                                when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                                                when nf.name = '__typename' then format('%L', nf.type_)
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
            meta_kind = 'Mutation.insert.one'
            and name = graphql.name_literal(ast);

    entity regclass = field_rec.entity;

    arg_object graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'ObjectArg';
    allowed_columns graphql.field[] = array_agg(field) from graphql.field where parent_arg_field_id = arg_object.id and meta_kind = 'Column';

    object_arg_ix int = graphql.arg_index(arg_object.name, variable_definitions);
    object_arg jsonb = graphql.get_arg_by_name(arg_object.name, graphql.jsonb_coalesce(ast -> 'arguments', '[]'));

    block_name text = graphql.slug();
    column_clause text;
    values_clause text;
    returning_clause text;
    result text;
begin

    if graphql.is_variable(object_arg -> 'value') then
        -- `object` is variable
        select
            string_agg(
                format(
                    '%I',
                    case
                        when ac.meta_kind = 'Column' then ac.column_name
                        else graphql.exception_unknown_field(x.key_, field_rec.type_)
                    end
                ),
                ', '
            ) as column_clause,
            string_agg(
                format(
                    '$%s::jsonb -> %L',
                    graphql.arg_index(
                        graphql.name_literal(object_arg -> 'value'),
                        variable_definitions
                    ),
                    x.key_
                ),
                ', '
            ) as values_clause
        from
            jsonb_each(variables -> graphql.name_literal(object_arg -> 'value')) x(key_, val)
            left join unnest(allowed_columns) ac
                on x.key_ = ac.name
        into
            column_clause, values_clause;

    else
        -- Literals and Column Variables
        select
            string_agg(
                format(
                    '%I',
                    case
                        when ac.meta_kind = 'Column' then ac.column_name
                        else graphql.exception_unknown_field(graphql.name_literal(val), field_rec.type_)
                    end
                ),
                ', '
            ) as column_clause,

            string_agg(
                case
                    when graphql.is_variable(val -> 'value') then format(
                        '$%s',
                        graphql.arg_index(
                            (val -> 'value' -> 'name' ->> 'value'),
                            variable_definitions
                        )
                    )
                    else format('%L', graphql.value_literal(val))
                end,
                ', '
            ) as values_clause
        from
            jsonb_array_elements(object_arg -> 'value' -> 'fields') arg_cols(val)
            left join unnest(allowed_columns) ac
                on graphql.name_literal(arg_cols.val) = ac.name
        into
            column_clause, values_clause;

    end if;

    returning_clause = format(
        'jsonb_build_object( %s )',
        string_agg(
            format(
                '%L, %s',
                graphql.alias_or_name_literal(x.sel),
                case
                    when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                    when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                    when nf.name = '__typename' then format('%L', nf.type_)
                    when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                        ast := x.sel,
                        variable_definitions := variable_definitions,
                        variables := variables,
                        parent_type := field_rec.type_,
                        parent_block_name := block_name
                    )
                    when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                        ast := x.sel,
                        variable_definitions := variable_definitions,
                        variables := variables,
                        parent_type := field_rec.type_,
                        parent_block_name := block_name
                    )
                    else graphql.exception_unknown_field(graphql.name_literal(x.sel), field_rec.type_)
                end
            ),
            ','
        )
    )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
        left join graphql.field nf
            on field_rec.type_ = nf.parent_type
            and graphql.name_literal(x.sel) = nf.name;

    result = format(
        'insert into %s as %I (%s) values (%s) returning %s;',
        entity,
        block_name,
        column_clause,
        values_clause,
        coalesce(returning_clause, 'null')
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
    language plpgsql
as $$
declare
    block_name text = graphql.slug();
    field graphql.field = gf from graphql.field gf where gf.name = graphql.name_literal(ast) and gf.parent_type = $4;
    type_ graphql.type = gt from graphql.type gt where gt.name = field.type_;
    result text;
begin
    return
        E'(\nselect\njsonb_build_object(\n'
        || string_agg(quote_literal(graphql.alias_or_name_literal(x.sel)) || E',\n' ||
            case
                when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                when nf.name = '__typename' then quote_literal(type_.name)
                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                    ast := x.sel,
                    variable_definitions := variable_definitions,
                    variables := variables,
                    parent_type := field.type_,
                    parent_block_name := block_name
                )
                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                    ast := x.sel,
                    variable_definitions := variable_definitions,
                    variables := variables,
                    parent_type := field.type_,
                    parent_block_name := block_name
                )
                else graphql.exception_unknown_field(graphql.name_literal(x.sel), field.type_)
            end,
            E',\n'
        )
        || ')'
        || format('
    from
        %s as %s
    where
        true
        -- join clause
        and %s
        -- filter clause
        and %s = %s
    limit 1
)
',
    type_.entity,
    quote_ident(block_name),
    coalesce(graphql.join_clause(field.local_columns, block_name, field.foreign_columns, parent_block_name), 'true'),
    'true',
    'true'
    )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
        left join graphql.field nf
            on nf.parent_type = field.type_
            and graphql.name_literal(x.sel) = nf.name
    where
        field.name = graphql.name_literal(ast)
        and $4 = field.parent_type;
end;
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
                    '%I = $%s::jsonb -> %L',
                    case
                        when ac.column_name is not null then ac.column_name
                        else graphql.exception_unknown_field(x.key_, f.type_)
                    end,
                    graphql.arg_index(
                        graphql.name_literal(set_arg -> 'value'),
                        variable_definitions
                    ),
                    x.key_
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
                        '%I = $%s',
                        case
                            when ac.meta_kind = 'Column' then ac.column_name
                            else graphql.exception_unknown_field(graphql.name_literal(val), field_rec.type_)
                        end,
                        graphql.arg_index(
                            (val -> 'value' -> 'name' ->> 'value'),
                            variable_definitions
                        )
                    )
                    else format(
                        '%I = %L',
                        case
                            when ac.meta_kind = 'Column' then ac.column_name
                            else graphql.exception_unknown_field(graphql.name_literal(val), field_rec.type_)
                        end,
                        graphql.value_literal(val)
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
                            top_fields.type_
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
                                                when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                                                when nf.name = '__typename' then format('%L', nf.type_)
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

    field_rec = graphql.array_first(field_recs);

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
create or replace function graphql.resolve_mutation_type(ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select
        -- check mutations exist
        case exists(select 1 from graphql.field where parent_type = 'Mutation' and not is_hidden_from_schema)
            when true then (
                select
                    coalesce(
                        jsonb_object_agg(
                            fa.field_alias,
                            case
                                when selection_name = 'name' then 'Mutation'
                                when selection_name = 'description' then null
                                else graphql.exception_unknown_field(selection_name, 'Mutation')
                            end
                        ),
                        'null'::jsonb
                    )
                from
                    jsonb_path_query(ast, '$.selectionSet.selections') selections,
                    lateral( select sel from jsonb_array_elements(selections) s(sel) ) x(sel),
                    lateral (
                        select
                            graphql.alias_or_name_literal(x.sel) field_alias,
                            graphql.name_literal(x.sel) as selection_name
                    ) fa
        )
    end
$$;
create or replace function graphql.resolve_query_type(ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select
        coalesce(
            jsonb_object_agg(
                fa.field_alias,
                case
                    when selection_name = 'name' then 'Query'
                    when selection_name = 'description' then null
                    else graphql.exception_unknown_field(selection_name, 'Query')
                end
            ),
            'null'::jsonb
        )
    from
        jsonb_path_query(ast, '$.selectionSet.selections') selections,
        lateral( select sel from jsonb_array_elements(selections) s(sel) ) x(sel),
        lateral (
            select
                graphql.alias_or_name_literal(x.sel) field_alias,
                graphql.name_literal(x.sel) as selection_name
        ) fa
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
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), graphql.resolve_query_type(node_field));

        elsif node_field_rec.name = 'mutationType' then
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), graphql.resolve_mutation_type(node_field));

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
create or replace function graphql.cache_key(role regrole, ast jsonb, variables jsonb)
    returns text
    language sql
    immutable
as $$
    select
        -- Different roles may have different levels of access
        graphql.sha1(
            $1::text
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
create type graphql.operation as enum ('query', 'mutation');


create or replace function graphql.resolve(stmt text, variables jsonb = '{}')
    returns jsonb
    volatile
    strict
    language plpgsql
as $$
declare
    ---------------------
    -- Always required --
    ---------------------
    parsed graphql.parse_result = graphql.parse(stmt);
    ast jsonb = parsed.ast;
    variable_definitions jsonb = coalesce(graphql.variable_definitions_sort(ast -> 'definitions' -> 0 -> 'variableDefinitions'), '[]');

    prepared_statement_name text = graphql.cache_key(current_user::regrole, ast, variables);

    q text;
    data_ jsonb;
    errors_ text[] = case when parsed.error is null then '{}' else array[parsed.error] end;

    operation graphql.operation;

    ---------------------
    -- If not in cache --
    ---------------------

    -- AST without location info ("loc" key)
    ast_locless jsonb;

    -- ast with fragments inlined
    fragment_definitions jsonb;
    ast_inlined jsonb;
    ast_operation jsonb;

    meta_kind graphql.meta_kind;
    field_meta_kind graphql.field_meta_kind;

    -- Exception stack
    error_message text;
begin
    -- Build query if not in cache
    if errors_ = '{}' and not graphql.prepared_statement_exists(prepared_statement_name) then

        begin

            ast_locless = graphql.ast_pass_strip_loc(ast);
            fragment_definitions = jsonb_path_query_array(ast_locless, '$.definitions[*] ? (@.kind == "FragmentDefinition")');
            -- Skip fragment inline when no fragments are present
            ast_inlined = case
                when fragment_definitions = '[]'::jsonb then ast_locless
                else graphql.ast_pass_fragments(ast_locless, fragment_definitions)
            end;

            -- Query or Mutation?
            operation = ast_inlined -> 'definitions' -> 0 ->> 'operation';
            ast_operation = ast_inlined -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0;

            if operation = 'mutation' then
                field_meta_kind = f.meta_kind
                    from
                        graphql.field f
                    where
                        f.parent_type = 'Mutation'
                        and f.name = graphql.name_literal(ast_operation);

                if field_meta_kind is null then
                    perform graphql.exception_unknown_field(
                        graphql.name_literal(ast_operation),
                        'Mutation'
                    );
                end if;

                q = case field_meta_kind
                    when 'Mutation.insert.one' then
                        graphql.build_insert(
                            ast := ast_operation,
                            variable_definitions := variable_definitions,
                            variables := variables
                        )
                    when 'Mutation.delete' then
                        graphql.build_delete(
                            ast := ast_operation,
                            variable_definitions := variable_definitions,
                            variables := variables
                        )
                    when 'Mutation.update' then
                        graphql.build_update(
                            ast := ast_operation,
                            variable_definitions := variable_definitions,
                            variables := variables
                        )
                end;

            elsif operation = 'query' then

                meta_kind = type_.meta_kind
                    from
                        graphql.field
                        join graphql.type type_
                            on field.type_ = type_.name
                    where
                        field.parent_type = 'Query'
                        and field.name = graphql.name_literal(ast_operation);

                if meta_kind is null then
                    perform graphql.exception_unknown_field(
                        graphql.name_literal(ast_operation),
                        'Query'
                    );
                end if;

                q = case meta_kind
                    when 'Connection' then
                        graphql.build_connection_query(
                            ast := ast_operation,
                            variable_definitions := variable_definitions,
                            variables := variables,
                            parent_type :=  'Query',
                            parent_block_name := null
                        )
                    else null::text
                end;

                data_ = case meta_kind
                    when '__Schema' then
                        graphql."resolve___Schema"(
                            ast := ast_operation,
                            variable_definitions := variable_definitions
                        )
                    when '__Type' then
                        jsonb_build_object(
                            graphql.name_literal(ast_operation),
                            graphql."resolve___Type"(
                                (
                                    select
                                        name
                                    from
                                        graphql.type type_
                                    where
                                        name = graphql.argument_value_by_name('name', ast_operation)
                                ),
                                ast_operation
                            )
                        )
                    else null::jsonb
                end;
            end if;

        exception when others then
            -- https://stackoverflow.com/questions/56595217/get-error-message-from-error-code-postgresql
            get stacked diagnostics error_message = MESSAGE_TEXT;
            errors_ = errors_ || error_message;
        end;

    end if;

    if errors_ = '{}' and q is not null then
        begin
            execute graphql.prepared_statement_create_clause(prepared_statement_name, variable_definitions, q);
        exception when others then
            get stacked diagnostics error_message = MESSAGE_TEXT;
            errors_ = errors_ || error_message;
        end;
    end if;

    if errors_ = '{}' and data_ is null then
        begin
            -- Call prepared statement respecting passed values and variable definition defaults
            execute graphql.prepared_statement_execute_clause(prepared_statement_name, variable_definitions, variables) into data_;
            data_ = jsonb_build_object(
                graphql.alias_or_name_literal(ast -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0),
                data_
            );
        exception when others then
            -- https://stackoverflow.com/questions/56595217/get-error-message-from-error-code-postgresql
            get stacked diagnostics error_message = MESSAGE_TEXT;
            errors_ = errors_ || error_message;
        end;
    end if;

    return jsonb_build_object(
        'data', data_,
        'errors', to_jsonb(errors_)
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
create or replace function graphql.rebuild_schema()
    returns void
    language plpgsql
as $$
begin
    truncate table graphql._field;
    delete from graphql._type;
    refresh materialized view graphql.entity with data;
    perform graphql.rebuild_types();
    perform graphql.rebuild_fields();
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
            perform graphql.rebuild_schema();
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
                perform graphql.rebuild_schema();
            end if;
    end loop;
end;
$$;

select graphql.rebuild_schema();

create event trigger graphql_watch_ddl
    on ddl_command_end
    execute procedure graphql.rebuild_on_ddl();

create event trigger graphql_watch_drop
    on sql_drop
    execute procedure graphql.rebuild_on_drop();
