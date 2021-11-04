create schema if not exists gql;

-------------
-- Hashing --
-------------
create or replace function gql.sha1(text)
    returns text
    strict
    immutable
    language sql
as $$
    select encode(digest($1, 'sha1'), 'hex')
$$;


-----------
-- JSONB --
-----------
create or replace function gql.jsonb_coalesce(val jsonb, default_ jsonb)
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

-----------
-- Array --
-----------
create or replace function gql.array_first(arr anyarray)
    returns anyelement
    language sql
    immutable
as
$$
    -- First element of an array
    select arr[1];
$$;

create or replace function gql.array_last(arr anyarray)
    returns anyelement
    language sql
    immutable
as
$$
    -- Last element of an array
    select arr[array_length(arr, 1)];
$$;


-------------------------
-- Entity Manipulation --
-------------------------
create function gql.to_regclass(schema_ text, name_ text)
    returns regclass
    language sql
    immutable
as
$$ select (quote_ident(schema_) || '.' || quote_ident(name_))::regclass; $$;


create function gql.to_table_name(regclass)
    returns text
    language sql
    immutable
as
$$ select coalesce(nullif(split_part($1::text, '.', 2), ''), $1::text) $$;


-------------------
-- String Casing --
-------------------

create function gql.to_pascal_case(text)
    returns text
    language sql
    immutable
as
$$
select
    string_agg(initcap(part), '')
from
    unnest(string_to_array($1, '_')) x(part)
$$;


create function gql.to_camel_case(text)
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



-------------------
-- Introspection --
-------------------
create or replace function gql.primary_key_columns(entity regclass)
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


create or replace function gql.primary_key_types(entity regclass)
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


----------------------
-- AST Manipulation --
----------------------

create function gql._parse(text)
    returns text
    language c
    immutable
as 'pg_graphql';

create function gql.parse(text)
    returns jsonb
    language sql
    immutable
as $$
    select gql._parse($1)::jsonb

$$;


create function gql.ast_pass_strip_loc(body jsonb)
returns jsonb
language sql
immutable
as $$
/*
Recursively remove a 'loc' key from a jsonb object by name
*/
    select
        case
            when jsonb_typeof(body) = 'object' then
                (
                    select
                        jsonb_object_agg(key_, gql.ast_pass_strip_loc(value_))
                    from
                        jsonb_each(body) x(key_, value_)
                    where
                        x.key_ <> 'loc'
                    limit
                        1
                )
            when jsonb_typeof(body) = 'array' then
                (
                    select
                        jsonb_agg(gql.ast_pass_strip_loc(value_))
                    from
                        jsonb_array_elements(body) x(value_)
                    limit
                        1
                )
            else
                body
        end;
$$;

create or replace function gql.ast_pass_fragments(ast jsonb, fragment_defs jsonb = '{}')
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
                            jsonb_object_agg(key_, gql.ast_pass_fragments(value_, fragment_defs))
                        from
                            jsonb_each(ast) x(key_, value_)
                    )
            when jsonb_typeof(ast) = 'array' then
                coalesce(
                    (
                        select
                            jsonb_agg(gql.ast_pass_fragments(value_, fragment_defs))
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
                                select gql.ast_pass_fragments(raw_frag_def, fragment_defs) as frag
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



create or replace function gql.name(ast jsonb)
    returns text
    immutable
    language sql
as $$
    select ast -> 'name' ->> 'value';
$$;


create or replace function gql.alias_or_name(field jsonb)
    returns text
    language sql
    immutable
    strict
as $$
    select coalesce(field -> 'alias' ->> 'value', field -> 'name' ->> 'value')
$$;


------------
-- CURSOR --
------------
-- base64 encoded utf-8 jsonb array of [schema_name, table_name, pkey_val1, pkey_val2 ...]

create or replace function gql.cursor_decode(cursor_ text)
    returns jsonb
    language sql
    immutable
    strict
as $$
    -- Decodes a base64 encoded jsonb array of [schema_name, table_name, pkey_val1, pkey_val2, ...]
    -- Example:
    --        select gql.cursor_decode('WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd')
    --        ["public", "account", 1]
    select convert_from(decode(cursor_, 'base64'), 'utf-8')::jsonb
$$;


create or replace function gql.cursor_encode(contents jsonb)
    returns text
    language sql
    immutable
    strict
as $$
    -- Encodes a jsonb array of [schema_name, table_name, pkey_val1, pkey_val2, ...] to a base64 encoded string
    -- Example:
    --        select gql.cursor_encode('["public", "account", 1]'::jsonb)
    --        'WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd'
    select encode(convert_to(contents::text, 'utf-8'), 'base64')
$$;



create or replace function gql.cursor_row_clause(entity regclass, alias_name text)
    returns text
    language sql
    immutable
    as
$$
    -- SQL string returning decoded cursor for an aliased table
    -- Example:
    --        select gql.cursor_row_clause('public.account', 'abcxyz')
    --        row('public', 'account', abcxyz.id)
    select
        'row('
        || format('%L::text,', quote_ident(entity::text))
        || string_agg(quote_ident(alias_name) || '.' || quote_ident(x), ',')
        ||')'
    from unnest(gql.primary_key_columns(entity)) pk(x)
$$;


create or replace function gql.cursor_encoded_clause(entity regclass, alias_name text)
    returns text
    language sql
    immutable
    as
$$
    -- SQL string returning encoded cursor for an aliased table
    -- Example:
    --        select gql.cursor_encoded_clause('public.account', 'abcxyz')
    --        gql.cursor_encode(jsonb_build_array('public', 'account', abcxyz.id))
    select
        'gql.cursor_encode(jsonb_build_array('
        || format('%L::text,', quote_ident(entity::text))
        || string_agg(quote_ident(alias_name) || '.' || quote_ident(x), ',')
        ||'))'
    from unnest(gql.primary_key_columns(entity)) pk(x)
$$;


create or replace function gql.cursor_clause_for_variable(entity regclass, variable_idx int)
    returns text
    language sql
    immutable
    strict
as $$
    -- SQL string to decode a cursor and convert it to a record for equality or pagination
    -- Example:
    --        select gql.cursor_clause_for_variable('public.account', 1)
    --        row(gql.cursor_decode($1)::text, gql.cursor_decode($1)::text, gql.cursor_decode($1)::integer)
    select
        'row(' || string_agg(format('(gql.cursor_decode($%s) ->> %s)::%s', variable_idx, ctype.idx-1, ctype.val), ', ') || ')'
    from
        unnest(array['text'::regtype] || gql.primary_key_types(entity)) with ordinality ctype(val, idx);
$$;

create or replace function gql.cursor_clause_for_literal(cursor_ text)
    returns text
    language sql
    immutable
    as
$$
    -- SQL string
    -- Example:
    --        select gql.cursor_clause_for_literal('WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd')
    --        row('public','account','2')
    -- Note:
    --         Type casts are not necessary because the values are visible to the planner allowing coercion
    select 'row(' || string_agg(quote_literal(x), ',') || ')'
    from jsonb_array_elements_text(convert_from(decode(cursor_, 'base64'), 'utf-8')::jsonb) y(x)
$$;

--------------------------
-- Table/View/Type Defs --
--------------------------

create type gql.cardinality as enum ('ONE', 'MANY');


-- https://github.com/graphql/graphql-js/blob/main/src/type/introspection.ts#L197
create type gql.type_kind as enum ('SCALAR', 'OBJECT', 'INTERFACE', 'UNION', 'ENUM', 'INPUT_OBJECT', 'LIST', 'NON_NULL');


create type gql.meta_kind as enum (
    'NODE', 'EDGE', 'CONNECTION', 'CUSTOM_SCALAR', 'PAGE_INFO',
    'CURSOR', 'QUERY', 'MUTATION', 'BUILTIN', 'INTERFACE',
    -- Introspection types
    '__SCHEMA', '__TYPE', '__TYPE_KIND', '__FIELD', '__INPUT_VALUE', '__ENUM_VALUE', '__DIRECTIVE', '__DIRECTIVE_LOCATION'
);


create or replace view gql.entity as
select
    oid::regclass as entity
from
    pg_class
where
    relkind = ANY (ARRAY['r', 'p'])
    and not relnamespace = ANY (ARRAY['information_schema'::regnamespace, 'pg_catalog'::regnamespace, 'gql'::regnamespace])
    and pg_catalog.has_schema_privilege(current_user, relnamespace, 'USAGE')
    and pg_catalog.has_any_column_privilege(oid::regclass, 'SELECT');


create or replace view gql.relationship as
    with rels as materialized (
        select
            const.conname as constraint_name,
            e.entity as local_entity,
            array_agg(local_.attname::text order by l.col_ix asc) as local_columns,
            'MANY'::gql.cardinality as local_cardinality,
            const.confrelid::regclass as foreign_entity,
            array_agg(ref_.attname::text order by r.col_ix asc) as foreign_columns,
            'ONE'::gql.cardinality as foreign_cardinality
        from
            gql.entity e
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


create or replace view gql.type as
select
    name,
    type_kind::gql.type_kind,
    meta_kind::gql.meta_kind,
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
    ('Query', 'OBJECT', 'QUERY', null),
    ('Mutation', 'OBJECT', 'MUTATION', null),
    ('PageInfo', 'OBJECT', 'PAGE_INFO', null),
    -- Introspection System
    ('__TypeKind', 'ENUM', '__TYPE_KIND', 'An enum describing what kind of type a given `__Type` is.'),
    ('__Schema', 'OBJECT', '__SCHEMA', 'A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.'),
    ('__Type', 'OBJECT', '__TYPE', 'The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the `__TypeKind` enum.\n\nDepending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional `specifiedByURL`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.'),
    ('__Field', 'OBJECT', '__FIELD', 'Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.'),
    ('__InputValue', 'OBJECT', '__INPUT_VALUE', 'Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.'),
    ('__EnumValue', 'OBJECT', '__ENUM_VALUE', 'One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.'),
    ('__DirectiveLocation', 'ENUM', '__DIRECTIVE_LOCATION', 'A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.'),
    ('__Directive', 'OBJECT', '__DIRECTIVE', 'A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.\n\nIn some cases, you need to provide options to alter GraphQL execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.')
) as const(name, type_kind, meta_kind, description)
union all
select
    x.*
from
    gql.entity ent,
    lateral (
        select
            gql.to_pascal_case(gql.to_table_name(ent.entity)) table_name_pascal_case
    ) names_,
    lateral (
        values
            (names_.table_name_pascal_case::text, 'OBJECT'::gql.type_kind, 'NODE'::gql.meta_kind, null::text, ent.entity),
            (names_.table_name_pascal_case || 'Edge', 'OBJECT', 'EDGE', null, ent.entity),
            (names_.table_name_pascal_case || 'Connection', 'OBJECT', 'CONNECTION', null, ent.entity)
    ) x
union all
select
    gql.to_pascal_case(t.typname), 'ENUM', 'CUSTOM_SCALAR', null, null
from
    pg_type t
    join pg_enum e
        on t.oid = e.enumtypid
where
    t.typnamespace not in ('information_schema'::regnamespace, 'pg_catalog'::regnamespace, 'gql'::regnamespace)
    and pg_catalog.has_type_privilege(current_user, t.oid, 'USAGE');


create or replace view gql.enum_value as
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
        ('__DirectiveLocation', 'INPUT_FIELD_DEFINITION', 'Location adjacent to an input object field definition.')
) x(type_, value, description)
union all
select
    gql.to_pascal_case(t.typname),
    e.enumlabel as value,
    null::text
from
    pg_type t
    join pg_enum e
        on t.oid = e.enumtypid
    join pg_catalog.pg_namespace n
        on n.oid = t.typnamespace
where
    n.nspname not in ('gql', 'information_schema', 'pg_catalog')
    and pg_catalog.has_type_privilege(current_user, t.oid, 'USAGE');


create function gql.sql_type_to_gql_type(sql_type text)
    returns text
    language sql
as
$$
    -- SQL type from information_schema.columns.data_type
    select
        case
            when sql_type like 'int%' then 'Int'
            when sql_type like 'bool%' then 'Boolean'
            when sql_type like 'float%' then 'Float'
            when sql_type like 'numeric%' then 'Float'
            when sql_type like 'json%' then 'JSON'
            when sql_type = 'uuid' then 'UUID'
            when sql_type like 'date%' then 'DateTime'
            when sql_type like 'timestamp%' then 'DateTime'
        else 'String'
    end;
$$;


create or replace view gql.field as
select
    parent_type,
    type_,
    name,
    is_not_null,
    is_array,
    is_array_not_null,
    description,
    null::text as column_name,
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
        ('__Type', '__Field', 'fields', true, true, false, null),
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
        fs.*
    from
        gql.type conn
        join gql.type edge
            on conn.entity = edge.entity
            and conn.meta_kind = 'CONNECTION'
            and edge.meta_kind = 'EDGE'
        join gql.type node
            on edge.entity = node.entity
            and node.meta_kind = 'NODE',
        lateral (
            values
                (node.name, 'String', '__typename', true, false, null, null, null, null, null, true),
                (edge.name, 'String', '__typename', true, false, null, null, null, null, null, true),
                (conn.name, 'String', '__typename', true, false, null, null, null, null, null, true),
                (edge.name, node.name, 'node', false, false, null::boolean, null::text, null::text, null::text[], null::text[], false),
                (edge.name, 'String', 'cursor', true, false, null, null, null, null, null, false),
                (conn.name, edge.name, 'edges', false, true, false, null, null, null, null, false),
                (conn.name, 'PageInfo', 'pageInfo', true, false, null, null, null, null, null, false),
                (conn.name, 'Int', 'totalCount', true, false, null, null, null, null, null, false),
                (node.name, 'ID', 'nodeId', true, false, null, null, null, null, null, false),
                ('Query', node.name, gql.to_camel_case(gql.to_table_name(node.entity)), false, false, null, null, null, null, null, false),
                ('Query', conn.name, gql.to_camel_case('all_' || gql.to_table_name(conn.entity) || 's'), false, false, null, null, null, null, null, false)
        ) fs(parent_type, type_, name, is_not_null, is_array, is_array_not_null, description, column_name, parent_columns, local_columns, is_hidden_from_schema)
    -- Node
    -- Node.<column>
    union all
    select
        gt.name parent_type,
        -- substring removes the underscore prefix from array types
        gql.sql_type_to_gql_type(regexp_replace(tf.type_str, '\[\]$', '')) as type_,
        gql.to_camel_case(pa.attname::text) as name,
        pa.attnotnull as is_not_null,
        tf.type_str like '%[]' as is_array,
        pa.attnotnull and tf.type_str like '%[]' as is_array_not_null,
        null::text description,
        pa.attname::text as column_name,
        null::text[],
        null::text[],
        false
    from
        gql.type gt
        join pg_attribute pa
            on gt.entity = pa.attrelid,
        lateral (
            select pg_catalog.format_type(atttypid, atttypmod) type_str
        ) tf
    where
        gt.meta_kind = 'NODE'
        and pa.attnum > 0
        and pg_catalog.has_column_privilege(current_user, gt.entity, pa.attname, 'SELECT')
    union all
    -- Node.<relationship>
    -- Node.<connection>
    select
        node.name parent_type,
        conn.name type_,
        case
            when (
                conn.meta_kind = 'CONNECTION'
                and rel.foreign_cardinality = 'MANY'
            ) then gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) || 's'

            -- owner_id -> owner
            when (
                conn.meta_kind = 'NODE'
                and rel.foreign_cardinality = 'ONE'
                and array_length(rel.local_columns, 1) = 1
                and rel.local_columns[1] like '%_id'
            ) then gql.to_camel_case(left(rel.local_columns[1], -3))

            when rel.foreign_cardinality = 'ONE' then gql.to_camel_case(gql.to_table_name(rel.foreign_entity))

            else gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) || 'RequiresNameOverride'
        end,
        -- todo
        false as is_not_null,
        rel.foreign_cardinality = 'MANY' as is_array,
        case when rel.foreign_cardinality = 'MANY' then false else null end as is_array_not_null,
        null description,
        null column_name,
        rel.local_columns,
        rel.foreign_columns,
        false
    from
        gql.type node
        join gql.relationship rel
            on node.entity = rel.local_entity
        join gql.type conn
            on conn.entity = rel.foreign_entity
            and (
                (conn.meta_kind = 'NODE' and rel.foreign_cardinality = 'ONE')
                or (conn.meta_kind = 'CONNECTION' and rel.foreign_cardinality = 'MANY')
            )
    where
        node.meta_kind = 'NODE';

-- Arguments
create or replace view gql.arg as
-- TODO(OR): is_deprecated field?
-- __Field(includeDeprecated)
select f.name as field, 'includeDeprecated' as name, 'Boolean' as type_, false as is_not_null, 'f' as default_value
from gql.field f
where
    f.type_ = '__Field'
    and f.is_array
union all
-- __enumValue(includeDeprecated)
select f.name, 'includeDeprecated', 'Boolean', false, 'f'
from gql.field f
where
    f.type_ = '__enumValue'
    and f.is_array
union all
-- __InputFields(includeDeprecated)
select f.name, 'includeDeprecated', 'Boolean', false, 'f'
from gql.field f
where
    f.type_ = '__InputFields'
    and f.is_array
union all
-- __type(name)
select
    f.name,
    'name' as name,
    'String' type_,
    true as is_not_null,
    null
from gql.field f
where f.name = '__type'
union all
-- Node(id)
select
    f.name,
    'id' as name,
    'ID' type_,
    true as is_not_null,
    null
from
    gql.type t
    inner join gql.field f
        on t.name = f.type_
where
    t.meta_kind = 'NODE'
union all
-- Connection(first, last, after, before)
select
    f.name field, y.name_ as name, 'Int' type_, false as is_not_null, null
from
    gql.type t
    inner join gql.field f
        on t.name = f.type_,
    --lateral (select name_ from unnest(array['first', 'last']) x(name_)) y(name_)
    lateral (select name_ from unnest(array['first']) x(name_)) y(name_)
where t.meta_kind = 'CONNECTION'
union all
select
    f.name field, y.name_ as name, 'String' type_, false as is_not_null, null
from
    gql.type t
    inner join gql.field f
        on t.name = f.type_,
    --lateral (select name_ from unnest(array['before', 'after']) x(name_)) y(name_)
    lateral (select name_ from unnest(array['after']) x(name_)) y(name_)
where t.meta_kind = 'CONNECTION'
union all
-- Node(nodeId)
-- Restrict to entrypoint only?
select
    f.name field, 'nodeId' as name, 'ID' type_, true as is_not_null, null
from
    gql.type t
    inner join gql.field f
        on t.name = f.type_
where t.meta_kind = 'NODE';


-------------
-- Resolve --
-------------


create or replace function gql.primary_key_clause(entity regclass, alias_name text)
    returns text
    language sql
    immutable
    as
$$
    select '(' || string_agg(quote_ident(alias_name) || '.' || quote_ident(x), ',') ||')'
    from unnest(gql.primary_key_columns(entity)) pk(x)
$$;

create or replace function gql.join_clause(local_columns text[], local_alias_name text, parent_columns text[], parent_alias_name text)
    returns text
    language sql
    immutable
    as
$$
    -- select gql.join_clause(array['a', 'b', 'c'], 'abc', array['d', 'e', 'f'], 'def')
    select string_agg(quote_ident(local_alias_name) || '.' || quote_ident(x) || ' = ' || quote_ident(parent_alias_name) || '.' || quote_ident(y), ' and ')
    from
        unnest(local_columns) with ordinality local_(x, ix),
        unnest(parent_columns) with ordinality parent_(y, iy)
    where
        ix = iy
$$;


create or replace function gql.slug()
    returns text
    language sql
    volatile
as $$
    select substr(md5(random()::text), 0, 12);
$$;



create or replace function gql.build_node_query(
    ast jsonb,
    variables jsonb = '{}',
    variable_definitions jsonb = '[]',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language sql
as $$
    with b as (
        select gql.slug() as block_name
    ),
    field as (
        select * from gql.field gf where gf.name = gql.name(ast) and gf.parent_type = $4
    ),
    type_ as (
        select * from gql.type gt where gt.name = (select type_ from field)
    ),
    x(sel) as (
        select
            *
        from
            jsonb_array_elements(ast -> 'selectionSet' -> 'selections')
    ),
    args(pkey_safe) as (
        select
            case
                -- Provided via variable definition
                when defs.idx is not null then gql.cursor_clause_for_variable(type_.entity, defs.idx::int)
                -- Hard coded value
                else gql.cursor_clause_for_literal(ar.elem -> 'value' ->> 'value')
            end
        from
            jsonb_array_elements(gql.jsonb_coalesce(ast -> 'arguments', '[]'::jsonb)) ar(elem)
            join field
                on true
            join type_
                on true
            left join gql.arg ga
                on ga.field = field.name
            left join jsonb_array_elements(variable_definitions) with ordinality as defs(elem, idx)
                on (ar.elem -> 'value' ->> 'kind') = 'Variable'
                and gql.name(ar.elem -> 'value') = gql.name(defs.elem -> 'variable')
        limit 1
    )
    select
        E'(\nselect\njsonb_build_object(\n'
        || string_agg(quote_literal(gql.alias_or_name(x.sel)) || E',\n' ||
            case
                when nf.column_name is not null then (quote_ident(b.block_name) || '.' || quote_ident(nf.column_name))
                when nf.name = '__typename' then quote_literal(gt.name)
                when nf.name = 'nodeId' then gql.cursor_encoded_clause(gt.entity, b.block_name)
                when nf.local_columns is not null and nf.is_array then gql.build_connection_query(
                    ast := x.sel,
                    variables := variables,
                    variable_definitions := variable_definitions,
                    parent_type := gf.type_,
                    parent_block_name := b.block_name
                )
                when nf.local_columns is not null then gql.build_node_query(
                    ast := x.sel,
                    variables := variables,
                    variable_definitions := variable_definitions,
                    parent_type := gf.type_,
                    parent_block_name := b.block_name
                )
                else null::text
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
    gt.entity,
    quote_ident(b.block_name),
    coalesce(gql.join_clause(gf.local_columns, b.block_name, gf.parent_columns, parent_block_name), 'true'),
    case
        when args.pkey_safe is null then 'true'
        else gql.cursor_row_clause(gt.entity, b.block_name)
    end,
    case
        when args.pkey_safe is null then 'true'
        else args.pkey_safe
    end
    )
    from
        x
        join field gf -- top level
            on true
        left join args
            on true
        join type_ gt -- for gt.entity
            on true
        join gql.field nf -- selected fields (node_field_row)
            on nf.parent_type = gf.type_
            and gql.name(x.sel) = nf.name,
        b
    where
        gf.name = gql.name(ast)
        and $4 = gf.parent_type
    group by
        gt.entity, b.block_name, gf.parent_columns, gf.local_columns, args.pkey_safe
$$;




create or replace function gql.build_connection_query(
    ast jsonb,
    variables jsonb = '{}',
    variable_definitions jsonb = '[]',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language sql
as $$
with b(block_name) as (select gql.slug()),
ent(entity) as (
    select
        t.entity
    from
        gql.field f
        join gql.type t
            on f.type_ = t.name
    where
        f.name = gql.name(ast)
        and f.parent_type = $4
),
root(sel) as (select * from jsonb_array_elements(ast -> 'selectionSet' -> 'selections')),
field_row as (select * from gql.field f where f.name = gql.name(ast) and f.parent_type = $4),
total_count(sel, q) as (select root.sel, format('%L, coalesce(min(%I.%I), 0)', gql.alias_or_name(root.sel), b.block_name, '__total_count')  from root, b where gql.name(sel) = 'totalCount'),
args as (
    select
        min(case when gql.name(sel) = 'first' then coalesce(ar.sel -> 'value' ->> 'value') else null end) as first_val,
        min(null::text) as last_val
    from
        jsonb_array_elements(gql.jsonb_coalesce(ast -> 'arguments', '[]')) ar(sel)
),
page_info(sel, q) as (
    select
        root.sel,
        format('%L,
            jsonb_build_object(
                %s
            )
        ',
            gql.alias_or_name(root.sel),
        (select
            string_agg(
                format(
                    '%L, %s',
                    gql.alias_or_name(pi.sel),
                    case gql.name(pi.sel)
                        when 'startCursor' then format('gql.array_first(array_agg(%I.__cursor))', block_name)
                        when 'endCursor' then format('gql.array_last(array_agg(%I.__cursor))', block_name)
                        when 'hasNextPage' then format('gql.array_last(array_agg(%I.__cursor)) <> gql.array_first(array_agg(%I.__last_cursor))', block_name, block_name)
                        when 'hasPreviousPage' then format('gql.array_first(array_agg(%I.__cursor)) <> gql.array_first(array_agg(%I.__first_cursor))', block_name, block_name)
                        else 'INVALID_FIELD ' || gql.name(pi.sel)::text
                    end
                )
                , E',\n\t\t\t\t'
            )
         from
             jsonb_array_elements(root.sel -> 'selectionSet' -> 'selections') pi(sel)
        ))
    from
        root, b
    where
        gql.name(sel) = 'pageInfo'),
edges(sel, q) as (
    select
        root.sel,
        format('%L, json_agg(-- edges
            jsonb_build_object(%s) -- maybe cursor
            -- node
            %s
            )
        ',
        gql.alias_or_name(root.sel),
        (select
             format('%L, %I.%I', gql.alias_or_name(ec.sel), b.block_name, '__cursor')
         from
             jsonb_array_elements(root.sel -> 'selectionSet' -> 'selections') ec(sel) where gql.name(ec.sel) = 'cursor'
        ),
        (select
             format('|| jsonb_build_object(
                   %L, jsonb_build_object(
                           %s
                          )
                  )',
                   gql.alias_or_name(e.sel),
                    string_agg(
                        format(
                            '%L, %s',
                            gql.alias_or_name(n.sel),
                            case
                                when gf_s.name = '__typename' then quote_literal(gt_s.name)
                                when gf_s.column_name is not null then format('%I.%I', b.block_name, gf_s.column_name)
                                when gf_s.local_columns is not null and not gf_s.is_array then gql.build_node_query(
                                                                                    ast := n.sel,
                                                                                    variables := variables,
                                                                                    variable_definitions := variable_definitions,
                                                                                    parent_type := gf_n.type_,
                                                                                    parent_block_name := b.block_name
                                                                                )
                                when gf_s.local_columns is not null and gf_s.is_array then gql.build_connection_query(
                                                                                    ast := n.sel,
                                                                                    variables := variables,
                                                                                    variable_definitions := variable_definitions,
                                                                                    parent_type := gf_n.type_,
                                                                                    parent_block_name := b.block_name
                                                                                )
                                when gf_s.name = 'nodeId' then format('%I.%I', b.block_name, '__cursor')
                                else quote_literal('UNRESOLVED')
                            end
                        ),
                        E',\n\t\t\t\t\t\t'
                    )
            )
         from
            jsonb_array_elements(root.sel -> 'selectionSet' -> 'selections') e(sel), -- node (0 or 1)
            lateral jsonb_array_elements(e.sel -> 'selectionSet' -> 'selections') n(sel) -- node selection
            join field_row gf_c -- connection field
                 on true
             join gql.field gf_e -- edge field
                 on gf_c.type_ = gf_e.parent_type
                 and gf_e.name = 'edges'
            join gql.field gf_n -- node field
                 on gf_e.type_ = gf_n.parent_type
                 and gf_n.name = 'node'
             join gql.field gf_s -- node selections
                 on gf_n.type_ = gf_s.parent_type
                 and gql.name(n.sel) = gf_s.name
             join gql.type gt_s -- node selection type
                 on gf_n.type_ = gt_s.name
         where
             gql.name(e.sel) = 'node'
         group by
             e.sel
        ))
    from
        root, b
    where
        gql.name(sel) = 'edges')

select
    format('(
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
    from
    (
        select
            count(*) over () __total_count,
            first_value(%s) over (order by %s range between unbounded preceding and current row)::text as __first_cursor,
            last_value(%s) over (order by %s range between current row and unbounded following)::text as __last_cursor,
            %s::text as __cursor,
            *
        from
            %I as %s
        where
            true
            --pagination_clause
            -- join clause
            and %s
        order by
            %s asc
        limit %s
    ) as %s
)',
        (select coalesce(total_count.q, '') from total_count),
        (select coalesce(page_info.q, '') from page_info),
        (select coalesce(edges.q, '') from edges),
        gql.cursor_encoded_clause(entity, block_name),
        gql.primary_key_clause(entity, block_name) || ' asc',
        gql.cursor_encoded_clause(entity, block_name),
        gql.primary_key_clause(entity, block_name) || ' asc',
        gql.cursor_encoded_clause(entity, block_name),
        entity,
        quote_ident(block_name),
        coalesce(gql.join_clause(field_row.local_columns, block_name, field_row.parent_columns, parent_block_name), 'true'),
        gql.primary_key_clause(entity, block_name),
        -- limit here
        -- TODO(enforce only 1 provided)
        (select least(coalesce(args.first_val::int, args.last_val::int, 10), 10) from args),
        quote_ident(block_name)

          )
    from
        b,
        ent,
        field_row
$$;


create or replace function gql."resolve_enumValues"(type_ text, ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select jsonb_agg(
        jsonb_build_object(
            'description', value::text,
            'deprecationReason', null
        )
    )
    from
        gql.enum_value ev where ev.type_ = $1;
$$;


-- stubs for recursion
create or replace function gql.resolve___input_value(arg_id int, ast jsonb) returns jsonb language sql as $$ select 'STUB'::text::jsonb $$;
create or replace function gql."resolve___Type"(
    type_ text,
    ast jsonb,
    is_array_not_null bool = false,
    is_array bool = false,
    is_not_null bool = false
) returns jsonb language sql as $$ select 'STUB'::text::jsonb $$;

create or replace function gql.resolve_field(field text, parent_type text, ast jsonb) returns jsonb language sql as $$ select 'STUB'::text::jsonb $$;


create or replace function gql.resolve___input_value(arg_id int, ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select
        coalesce(
            jsonb_object_agg(
                fa.field_alias,
                case
                    when selection_name = 'name' then to_jsonb(ar.name)
                    when selection_name = 'description' then to_jsonb(ar.description)
                    when selection_name = 'defaultValue' then to_jsonb(ar.default_value)
                    when selection_name = 'isDeprecated' then to_jsonb(ar.is_deprecated)
                    when selection_name = 'deprecationReason' then to_jsonb(ar.deprecation_reason)
                    when selection_name = 'type' then gql."resolve___Type"(ar.type_, x.sel)
                    else to_jsonb('ERROR: Unknown Field'::text)
                end
            ),
            'null'::jsonb
        )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel),
        lateral (
            select
                gql.alias_or_name(x.sel) field_alias,
                gql.name(x.sel) as selection_name
        ) fa
        join gql.arg ar
            on ar.id = arg_id
$$;


create or replace function gql.resolve_field(field text, parent_type text, ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select
        coalesce(
            jsonb_object_agg(
                fa.field_alias,
                case
                    when selection_name = 'name' then to_jsonb(f.name)
                    when selection_name = 'description' then to_jsonb(f.description)
                    when selection_name = 'isDeprecated' then to_jsonb(false) -- todo
                    when selection_name = 'deprecationReason' then to_jsonb(null::text) -- todo
                    when selection_name = 'type' then gql."resolve___Type"(f.type_, x.sel, f.is_array_not_null, f.is_array, f.is_not_null)
                    when selection_name = 'args' then '[]'::jsonb --gql."resolve___InputValues"(f.type_, x.sel, f.is_array_not_null, f.is_array, f.is_not_null)
                    else to_jsonb('ERROR: Unknown Field'::text)
                end
            ),
            'null'::jsonb
        )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel),
        lateral (
            select
                gql.alias_or_name(x.sel) field_alias,
                gql.name(x.sel) as selection_name
        ) fa
        join gql.field f
            on f.name = field
            and f.parent_type = parent_type
$$;




create or replace function gql."resolve___Type"(type_ text, ast jsonb, is_array_not_null bool = false, is_array bool = false, is_not_null bool = false)
    returns jsonb
    stable
    language sql
as $$
    select
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
                        case
                            -- TODO, un-hardcode
                            when gt.name = 'Mutation' then '[]'::jsonb
                            else (select jsonb_agg(gql.resolve_field(f.name, f.parent_type, x.sel)) from gql.field f where f.parent_type = gt.name and not f.is_hidden_from_schema)
                        end
                    )
                    when selection_name = 'interfaces' and not has_modifiers then (
                        case
                            -- Scalars get null, objects get an empty list. This is a poor implementation
                            when (gt.meta_kind not in ('INTERFACE', 'BUILTIN', 'CURSOR') and gt.meta_kind::text not like '\_\_%') then '[]'::jsonb
                            else to_jsonb(null::text)
                        end
                    )
                    when selection_name = 'possibleTypes' and not has_modifiers then to_jsonb(null::text)
                    -- wasteful
                    when selection_name = 'enumValues' then gql."resolve_enumValues"(gt.name, x.sel)
                    when selection_name = 'inputFields' and not has_modifiers then to_jsonb(null::text)
                    when selection_name = 'ofType' then (
                        case
                            -- NON_NULL(LIST(...))
                            when is_array_not_null is true then gql."resolve___Type"(type_, x.sel, is_array_not_null := false, is_array := is_array, is_not_null := is_not_null)
                            -- LIST(...)
                            when is_array then gql."resolve___Type"(type_, x.sel, is_array_not_null := false, is_array := false, is_not_null := is_not_null)
                            -- NON_NULL(...)
                            when is_not_null then gql."resolve___Type"(type_, x.sel, is_array_not_null := false, is_array := false, is_not_null := false)
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
        gql.type gt
        join jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
            on true,
        lateral (
            select
                gql.alias_or_name(x.sel) field_alias,
                gql.name(x.sel) as selection_name
        ) fa,
        lateral (
            select (coalesce(is_array_not_null, false) or is_array or is_not_null) as has_modifiers
        ) hm
    where
        gt.name = type_
$$;


create or replace function gql."resolve_queryType"(ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select
        --jsonb_build_object(
        --    gql.name(ast),
            coalesce(
                jsonb_object_agg(
                    fa.field_alias,
                    case
                        when selection_name = 'name' then 'Query'
                        when selection_name = 'description' then null
                        else 'ERROR: Unknown Field'
                    end
                ),
                'null'::jsonb
            )
        --)
    from
        jsonb_path_query(ast, '$.selectionSet.selections') selections,
        lateral( select sel from jsonb_array_elements(selections) s(sel) ) x(sel),
        lateral (
            select
                gql.alias_or_name(x.sel) field_alias,
                gql.name(x.sel) as selection_name
        ) fa
$$;


create or replace function gql."resolve_mutationType"(ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select  coalesce(
                jsonb_object_agg(
                    fa.field_alias,
                    case
                        when selection_name = 'name' then 'Mutation'
                        when selection_name = 'description' then null
                        else 'ERROR: Unknown Field'
                    end
                ),
                'null'::jsonb
            )
    from
        jsonb_path_query(ast, '$.selectionSet.selections') selections,
        lateral( select sel from jsonb_array_elements(selections) s(sel) ) x(sel),
        lateral (
            select
                gql.alias_or_name(x.sel) field_alias,
                gql.name(x.sel) as selection_name
        ) fa
$$;


create or replace function gql."resolve___Schema"(
    ast jsonb,
    variables jsonb = '{}',
    variable_definitions jsonb = '[]'
)
    returns jsonb
    stable
    language plpgsql
    as $$
declare
    node_fields jsonb = jsonb_path_query(ast, '$.selectionSet.selections');
    node_field jsonb;
    node_field_rec gql.field;
    agg jsonb = '{}';
begin
    --field_rec = "field" from gql.field where parent_type = '__Schema' and name = field_name;

    for node_field in select * from jsonb_array_elements(node_fields) loop
        node_field_rec = "field" from gql.field where parent_type = '__Schema' and name = gql.name(node_field);

        if gql.name(node_field) = 'description' then
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), node_field_rec.description);
        elsif node_field_rec.type_ = '__Directive' then
            -- TODO
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), '[]'::jsonb);

        elsif node_field_rec.name = 'queryType' then
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), gql."resolve_queryType"(node_field));

        elsif node_field_rec.name = 'mutationType' then
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), gql."resolve_mutationType"(node_field));

        elsif node_field_rec.name = 'subscriptionType' then
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), null);

        elsif node_field_rec.name = 'types' then
            agg = agg || jsonb_build_object(
                    gql.alias_or_name(node_field),
                    jsonb_agg(gql."resolve___Type"(gt.name, node_field) order by gt.name)
                )
            from gql.type gt;


        elsif node_field_rec.type_ = '__Type' and not node_field_rec.is_array then
            agg = agg || gql."resolve___Type"(
                node_field_rec.type_,
                node_field,
                node_field_rec.is_array_not_null,
                node_field_rec.is_array,
                node_field_rec.is_not_null
            );

        else
            -- TODO, no mach
            perform 1;

        end if;
    end loop;

    return jsonb_build_object(gql.alias_or_name(ast), agg);
end
$$;


create or replace function gql.argument_value_by_name(name text, ast jsonb)
    returns text
    immutable
    language sql
as $$
    select jsonb_path_query_first(ast, ('$.arguments[*] ? (@.name.value == "' || name ||'")')::jsonpath) -> 'value' ->> 'value';
$$;


create or replace function gql.prepared_statement_create_clause(statement_name text, variable_definitions jsonb, query_ text)
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

create or replace function gql.prepared_statement_execute_clause(statement_name text, variable_definitions jsonb, variables jsonb)
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
            on gql.name(def -> 'variable') = var.key_
$$;


create or replace function gql.variable_definitioons_sort(variable_definitions jsonb)
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

create or replace function gql.prepared_statement_exists(statement_name text)
    returns boolean
    language sql
    stable
as $$
    select exists(select 1 from pg_prepared_statements where name = statement_name)
$$;


create or replace function gql.dispatch(stmt text, variables jsonb = '{}')
    returns jsonb
    volatile
    language plpgsql
as $$
declare
    ---------------------
    -- Always required --
    ---------------------
    prepared_statement_name text = gql.sha1(stmt);
    ast jsonb = gql.parse(stmt);
    variable_definitions jsonb = gql.variable_definitioons_sort(ast -> 'definitions' -> 0 -> 'variableDefinitions');

    q text;
    data_ jsonb;
    errors_ text[] = '{}';

    ---------------------
    -- If not in cache --
    ---------------------

    -- AST without location info ("loc" key)
    ast_locless jsonb;

    -- ast with fragments inlined
    fragment_definitions jsonb;
    ast_inlined jsonb;
    ast_operation jsonb;

    meta_kind gql.meta_kind;
begin
    -- Build query if not in cache
    if not gql.prepared_statement_exists(prepared_statement_name) then

        ast_locless = gql.ast_pass_strip_loc(ast);
        fragment_definitions = jsonb_path_query_array(ast_locless, '$.definitions[*] ? (@.kind == "FragmentDefinition")');
        ast_inlined =  gql.ast_pass_fragments(ast_locless, fragment_definitions);
        ast_operation = ast_inlined -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0;
        meta_kind = type_.meta_kind
            from
                gql.field
                join gql.type type_
                    on field.type_ = type_.name
            where
                field.parent_type = 'Query'
                and field.name = gql.name(ast_operation);

        q = case meta_kind
            when 'CONNECTION' then
                gql.build_connection_query(
                    ast := ast_operation,
                    variables := variables,
                    variable_definitions := variable_definitions,
                    parent_type :=  'Query',
                    parent_block_name := null
                )
            when 'NODE' then
                gql.build_node_query(
                    ast := ast_operation,
                    variables := variables,
                    variable_definitions := variable_definitions,
                    parent_type := 'Query',
                    parent_block_name := null
                )
            else null::text
        end;

        data_ = case meta_kind
            when '__SCHEMA' then
                gql."resolve___Schema"(
                    ast := ast_operation,
                    variables := variables,
                    variable_definitions := variable_definitions
                )
            when '__TYPE' then
                jsonb_build_object(
                    gql.name(ast_operation),
                    gql."resolve___Type"(
                        (select name from gql.type where name = gql.argument_value_by_name('name', ast_operation)),
                        ast_operation
                    )
                )
            else null::jsonb
        end;

    end if;

    if q is not null then
        execute gql.prepared_statement_create_clause(prepared_statement_name, variable_definitions, q);
    end if;

    if data_ is null then
        -- Call prepared statement respecting passed values and variable definition defaults
        execute gql.prepared_statement_execute_clause(prepared_statement_name, variable_definitions, variables) into data_;
        data_ = jsonb_build_object(
            gql.name(ast -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0),
            data_
        );
    end if;

    return jsonb_build_object(
        'data', data_,
        'errors', to_jsonb(errors_)
    );
end
$$;


grant all on schema gql to postgres;
grant all on all tables in schema gql to postgres;
