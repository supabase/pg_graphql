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
$$ select coalesce(nullif(split_part($1::text, '.', 2), ''), $1::text) $$;
create function graphql.to_camel_case(text)
    returns text
    language sql
    immutable
as
$$
select
    string_agg(
        case
            when part_ix = 1 then part
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
    entity regclass,
    graphql_type text,
    enum regtype,
    description text,
    unique (meta_kind, entity),
    check (entity is null or graphql_type is null)
);
create or replace function graphql.inflect_type_default(text)
    returns text
    language sql
    immutable
as $$
    select replace(initcap($1), '_', '');
$$;


create function graphql.type_name(rec graphql._type, dialect text = 'default')
    returns text
    language sql
    immutable
as $$
    select
        case
            when (rec).is_builtin then rec.meta_kind::text
            when dialect = 'default' then
                case rec.meta_kind
                    when 'Node'         then graphql.inflect_type_default(graphql.to_table_name(rec.entity))
                    when 'Edge'         then format('%sEdge',       graphql.inflect_type_default(graphql.to_table_name(rec.entity)))
                    when 'Connection'   then format('%sConnection', graphql.inflect_type_default(graphql.to_table_name(rec.entity)))
                    when 'OrderBy'      then format('%sOrderBy',    graphql.inflect_type_default(graphql.to_table_name(rec.entity)))
                    when 'FilterEntity' then format('%sFilter',     graphql.inflect_type_default(graphql.to_table_name(rec.entity)))
                    when 'FilterType'   then format('%sFilter',     rec.graphql_type)
                    when 'OrderByDirection' then rec.meta_kind::text
                    when 'PageInfo'     then rec.meta_kind::text
                    when 'Cursor'       then rec.meta_kind::text
                    when 'Query'        then rec.meta_kind::text
                    when 'Mutation'     then rec.meta_kind::text
                    when 'Enum'         then graphql.inflect_type_default(graphql.to_type_name(rec.enum))
                    else                graphql.exception('could not determine type name')
                end
            else graphql.exception('unknown dialect')
        end
$$;


create index ix_graphql_type_name_dialect_default on graphql._type(
    graphql.type_name(rec := _type, dialect := 'default'::text)
);
create view graphql.type as
    with d(dialect) as (
        select
            -- do not inline this call as it has a significant performance impact
            --coalesce(current_setting('graphql.dialect', true), 'default')
            'default'
    )
    select
       graphql.type_name(
            rec := t,
            dialect := d.dialect
       ) as name,
       t.*
    from
        graphql._type t,
        d
    where
        t.entity is null
        or pg_catalog.has_any_column_privilege(current_user, t.entity, 'SELECT');
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


create function graphql.sql_type_to_graphql_type(regtype)
    returns text
    language sql
as
$$
    select graphql.sql_type_to_graphql_type(pg_catalog.format_type($1, null))
$$;
create materialized view graphql.enum_value as
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
create or replace function graphql.rebuild_types()
    returns void
    language plpgsql
    as
$$
begin
    truncate table graphql._type cascade;
    alter sequence graphql._type_id_seq restart with 1;

    insert into graphql._type(type_kind, meta_kind, is_builtin, description)
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


    insert into graphql._type(type_kind, meta_kind, description, graphql_type)
       values
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Int"',      'Int'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Float"',    'Float'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "String"',   'String'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "Boolean"',  'Boolean'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "DateTime"', 'DateTime'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "BigInt"',   'BigInt'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "UUID"',     'UUID'),
            ('INPUT_OBJECT', 'FilterType', 'Boolean expression comparing fields on type "JSON"',     'JSON');


    insert into graphql._type(type_kind, meta_kind, description, entity)
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
            e.entity as local_entity,
            array_agg(local_.attname::text order by l.col_ix asc) as local_columns,
            'MANY'::graphql.cardinality as local_cardinality,
            const.confrelid::regclass as foreign_entity,
            array_agg(ref_.attname::text order by r.col_ix asc) as foreign_columns,
            'ONE'::graphql.cardinality as foreign_cardinality
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
                on l.col_ix = r.col_ix
        where
            const.contype = 'f'
        group by
            e.entity,
            const.conname,
            const.confrelid
    )
    select constraint_name, local_entity, local_columns, local_cardinality, foreign_entity, foreign_columns, foreign_cardinality from rels
    union all
    select constraint_name, foreign_entity, foreign_columns, foreign_cardinality, local_entity, local_columns, local_cardinality from rels;
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
create or replace function graphql.rebuild_schema()
    returns void
    language plpgsql
as $$
begin
    refresh materialized view graphql.entity with data;
    perform graphql.rebuild_types();
    perform graphql.rebuild_fields();
    refresh materialized view graphql.enum_value with data;
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
            'rule',
        )
        and obj.is_temporary IS false
        then
            perform graphql.rebuild_schema();
        end if
    end loop;
end;
$$;


create event trigger graphql_watch_ddl
    on ddl_command_end
    execute procedure graphql.rebuild_on_ddl();

create event trigger graphql_watch_drop
    on sql_drop
    execute procedure graphql.rebuild_on_ddl();
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
create or replace function graphql.arg_clause(name text, arguments jsonb, variable_definitions jsonb, entity regclass)
    returns text
    immutable
    language plpgsql
as $$
declare
    arg jsonb = graphql.get_arg_by_name(name, graphql.jsonb_coalesce(arguments, '[]'));

    is_opaque boolean = name in ('nodeId', 'before', 'after');

    res text;

    cast_to text = case
        when name in ('first', 'last') then 'int'
        else 'text'
    end;

begin
    if arg is null then
        return null;

    elsif graphql.is_variable(arg -> 'value') and is_opaque then
        return graphql.cursor_clause_for_variable(entity, graphql.arg_index(name, variable_definitions));

    elsif is_opaque then
        return graphql.cursor_clause_for_literal(arg -> 'value' ->> 'value');


    -- Order by

    -- Non-special variable
    elsif graphql.is_variable(arg -> 'value') then
        return '$' || graphql.arg_index(name, variable_definitions)::text || '::' || cast_to;

    -- Non-special literal
    else
        return format('%L::%s', (arg -> 'value' ->> 'value'), cast_to);
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

    -- Disallow variable order by clause because it is incompatible with prepared statements
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
                return graphql.exception('Invalid filter');
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
                return graphql.exception('Invalid filter');
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
    field_row graphql.field = f from graphql.field f where f.name = graphql.name_literal(ast) and f.parent_type = $4;
    first_ text = graphql.arg_clause('first',  (ast -> 'arguments'), variable_definitions, entity);
    last_ text = graphql.arg_clause('last',   (ast -> 'arguments'), variable_definitions, entity);
    before_ text = graphql.arg_clause('before', (ast -> 'arguments'), variable_definitions, entity);
    after_ text = graphql.arg_clause('after',  (ast -> 'arguments'), variable_definitions, entity);

    order_by_arg jsonb = graphql.get_arg_by_name('orderBy',  graphql.jsonb_coalesce((ast -> 'arguments'), '[]'));
    filter_arg jsonb = graphql.get_arg_by_name('filter',  graphql.jsonb_coalesce((ast -> 'arguments'), '[]'));

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
                                                        when 'hasNextPage' then format('graphql.array_last(array_agg(%I.__cursor)) <> graphql.array_first(array_agg(%I.__last_cursor))', block_name, block_name)
                                                        when 'hasPreviousPage' then format('graphql.array_first(array_agg(%I.__cursor)) <> graphql.array_first(array_agg(%I.__first_cursor))', block_name, block_name)
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
                                                                when gf_s.name = 'nodeId' then format('%I.%I', block_name, '__cursor')
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
                %I as %s
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
                        string_agg(format('%I.%I', block_name, column_name), ', '),
                        '1'
                    )
                from
                    graphql.field f
                    join graphql.type t
                        on f.parent_type = t.name
                where
                    f.column_name is not null
                    and t.entity = ent
                    and t.meta_kind = 'Node'
            ),
            -- from
            entity,
            quote_ident(block_name),
            -- pagination
            case when coalesce(after_, before_) is null then 'true' else graphql.cursor_row_clause(entity, block_name) end,
            case when after_ is not null then '>' when before_ is not null then '<' else '=' end,
            case when coalesce(after_, before_) is null then 'true' else coalesce(after_, before_) end,
            -- join
            coalesce(graphql.join_clause(field_row.local_columns, block_name, field_row.parent_columns, parent_block_name), 'true'),
            -- where
            graphql.where_clause(filter_arg, entity, block_name, variables, variable_definitions),
            -- order
            case
                when before_ is not null then graphql.order_by_clause(order_by_arg, entity, block_name, true, variables)
                else graphql.order_by_clause(order_by_arg, entity, block_name, false, variables)
            end,
            -- limit
            coalesce(first_, last_, '10'),
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
    nodeId text = graphql.arg_clause('nodeId', (ast -> 'arguments'), variable_definitions, type_.entity);
    result text;
begin
    return
        E'(\nselect\njsonb_build_object(\n'
        || string_agg(quote_literal(graphql.alias_or_name_literal(x.sel)) || E',\n' ||
            case
                when nf.column_name is not null then (quote_ident(block_name) || '.' || quote_ident(nf.column_name))
                when nf.name = '__typename' then quote_literal(type_.name)
                when nf.name = 'nodeId' then graphql.cursor_encoded_clause(type_.entity, block_name)
                when nf.local_columns is not null and nf_t.meta_kind = 'Connection' then graphql.build_connection_query(
                    ast := x.sel,
                    variable_definitions := variable_definitions,
                    variables := variables,
                    parent_type := field.type_,
                    parent_block_name := block_name
                )
                when nf.local_columns is not null and nf_t.meta_kind = 'Node' then graphql.build_node_query(
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
        %I as %s
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
    coalesce(graphql.join_clause(field.local_columns, block_name, field.parent_columns, parent_block_name), 'true'),
    case
        when nodeId is null then 'true'
        else graphql.cursor_row_clause(type_.entity, block_name)
    end,
    case
        when nodeId is null then 'true'
        else nodeId
    end
    )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
        left join graphql.field nf
            on nf.parent_type = field.type_
            and graphql.name_literal(x.sel) = nf.name
        left join graphql.type nf_t
            on nf.type_ = nf_t.name
    where
        field.name = graphql.name_literal(ast)
        and $4 = field.parent_type;
end;
$$;
create or replace function graphql."resolve_enumValues"(type_ text, ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    -- todo: remove overselection
    select jsonb_agg(
        jsonb_build_object(
            'name', value::text,
            'description', null::text,
            'isDeprecated', false,
            'deprecationReason', null
        )
    )
    from
        graphql.enum_value ev where ev.type_ = $1;
$$;
create or replace function graphql.resolve_field(field text, parent_type text, parent_arg_field_name text, ast jsonb)
    returns jsonb
    stable
    language plpgsql
as $$
declare
    field_rec graphql.field;
begin
    -- todo can this conflict for input types?
    field_rec = gf
        from
            graphql.field gf
        where
            gf.name = $1
            and gf.parent_type = $2
            and coalesce(gf.parent_arg_field_name, '') = coalesce($3, '');
    if field_rec is null then
        raise exception '% % %', $1, $2, $3;

    end if;

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
                                        field_rec.name,
                                        x.sel
                                    )
                                    order by ga.name
                                ),
                                '[]'
                            )
                        from
                            graphql.field ga
                        where
                            ga.parent_arg_field_name = field_rec.name
                            and not ga.is_hidden_from_schema
                            and ga.is_arg
                            and ga.parent_type = field_rec.type_ -- todo double check this join
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
create or replace function graphql."resolve_queryType"(ast jsonb)
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
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), graphql."resolve_queryType"(node_field));

        elsif node_field_rec.name = 'mutationType' then
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), 'null'::jsonb);

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
                        join (select distinct parent_type from graphql.field) gf
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
                            jsonb_agg(graphql.resolve_field(f.name, f.parent_type, null, x.sel))
                        from
                            graphql.field f
                        where
                            f.parent_type = gt.name
                            and not f.is_hidden_from_schema
                            and gt.type_kind = 'OBJECT'
                            and not f.is_arg
                            --and gt.type_kind not in ('SCALAR', 'ENUM', 'INPUT_OBJECT')
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
                            jsonb_agg(graphql.resolve_field(f.name, f.parent_type, null, x.sel))
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
    filter_clause as (
        select
            jpath::text as x
        from
            doc
        where
            jpath::text similar to '%."eq"|%."neq"'
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
        coalesce(string_agg(x, ','), '')
    from
        (
            select x from filter_clause
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
                format('execute %I (', statement_name)
                || string_agg(format('%L', coalesce(var.val, def ->> 'defaultValue')), ',' order by def_idx)
                || ')'
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
            ast_operation = ast_inlined -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0;
            meta_kind = type_.meta_kind
                from
                    graphql.field
                    join graphql.type type_
                        on field.type_ = type_.name
                where
                    field.parent_type = 'Query'
                    and field.name = graphql.name_literal(ast_operation);

            q = case meta_kind
                when 'Connection' then
                    graphql.build_connection_query(
                        ast := ast_operation,
                        variable_definitions := variable_definitions,
                        variables := variables,
                        parent_type :=  'Query',
                        parent_block_name := null
                    )
                when 'Node' then
                    graphql.build_node_query(
                        ast := ast_operation,
                        variable_definitions := variable_definitions,
                        variables := variables,
                        parent_type := 'Query',
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

        exception when others then
            -- https://stackoverflow.com/questions/56595217/get-error-message-from-error-code-postgresql
            get stacked diagnostics error_message = MESSAGE_TEXT;
            errors_ = errors_ || error_message;
        end;

    end if;

    if errors_ = '{}' and q is not null then
        execute graphql.prepared_statement_create_clause(prepared_statement_name, variable_definitions, q);
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
