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


create or replace function gql.to_schema_name(entity regclass)
    returns text
    language sql
    stable
as $$
    select
        nsp.nspname::text
    from
        pg_class pc
        join pg_namespace nsp
            on pc.relnamespace = nsp.oid
    where
        pc.oid = entity
$$;

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
        pg_index, pg_class, pg_attribute, pg_namespace
    where
        pg_class.oid = entity and
        indrelid = pg_class.oid and
        pg_class.relnamespace = pg_namespace.oid and
        pg_attribute.attrelid = pg_class.oid and
        pg_attribute.attnum = any(pg_index.indkey)
        and indisprimary
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
        pg_index, pg_class, pg_attribute, pg_namespace
    where
        pg_class.oid = entity and
        indrelid = pg_class.oid and
        pg_class.relnamespace = pg_namespace.oid and
        pg_attribute.attrelid = pg_class.oid and
        pg_attribute.attnum = any(pg_index.indkey)
        and indisprimary
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
        || format('%L::text,%L::text,', gql.to_schema_name(entity), gql.to_table_name(entity))
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
        || format('%L::text,%L::text,', gql.to_schema_name(entity), gql.to_table_name(entity))
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
        unnest(array['text'::regtype, 'text'::regtype] || gql.primary_key_types(entity)) with ordinality ctype(val, idx);
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


create table gql.entity (
    --id integer generated always as identity primary key,
    entity regclass primary key,
    is_disabled boolean default false
);


create or replace view gql.relationship as
    with constraint_cols as (
        select
            gql.to_regclass(table_schema::text, table_name::text) entity,
            constraint_name::text,
            table_schema::text as table_schema,
            array_agg(column_name::text) column_names
        from
            gql.entity ge
            join information_schema.constraint_column_usage ccu
                on ge.entity = gql.to_regclass(table_schema::text, table_name::text)
        group by table_schema,
            table_name,
            constraint_name
    ),
    directional as (
        select
            tc.constraint_name::text,
            gql.to_regclass(tc.table_schema::text, tc.table_name::text) local_entity,
            array_agg(kcu.column_name) local_columns,
            'MANY'::gql.cardinality as local_cardinality,
            ccu.entity foreign_entity,
            ccu.column_names::text[] as foreign_columns,
            'ONE'::gql.cardinality as foreign_cardinality
        from
            information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
            on tc.constraint_name = kcu.constraint_name
            and tc.table_schema = kcu.table_schema
        join constraint_cols as ccu
            on ccu.constraint_name = tc.constraint_name
            and ccu.table_schema = tc.table_schema
        where
            tc.constraint_type = 'FOREIGN KEY'
        group by
            tc.constraint_name,
            tc.table_schema,
            tc.table_name,
            ccu.entity,
            ccu.column_names
    )
    select *
    from
        directional
    union all
    select
        constraint_name,
        foreign_entity as local_entity,
        foreign_columns as local_columns,
        foreign_cardinality as local_cardinality,
        local_entity as foreign_entity,
        local_columns as foreign_columns,
        local_cardinality as foreign_cardinality
    from
        directional;

-- https://github.com/graphql/graphql-js/blob/main/src/type/introspection.ts#L197
--create type gql.type_kind as enum ('SCALAR', 'OBJECT', 'INTERFACE', 'UNION', 'ENUM', 'INPUT_OBJECT', 'LIST', 'NON_NULL');
create type gql.meta_kind as enum (
    'NODE', 'EDGE', 'CONNECTION', 'CUSTOM_SCALAR', 'PAGE_INFO',
    'CURSOR', 'QUERY', 'MUTATION', 'BUILTIN', 'INTERFACE',
    -- Introspection types
    '__SCHEMA', '__TYPE', '__TYPE_KIND', '__FIELD', '__INPUT_VALUE', '__ENUM_VALUE', '__DIRECTIVE', '__DIRECTIVE_LOCATION'
);

create table gql.enum_value(
    id integer generated always as identity primary key,
    type_id integer not null,
    value text not null,
    description text,
    unique (type_id, value)
);

create table gql.type (
    id integer generated always as identity primary key,
    name text not null unique,
    -- TODO triger enforce refers to __TypeKind
    type_kind_id integer not null references gql.enum_value(id) deferrable initially deferred,
    -- internal convenience designation
    meta_kind gql.meta_kind not null,
    description text,
    entity regclass references gql.entity(entity),
    -- Is it an input type
    is_input boolean not null default false,
    is_disabled boolean not null default false,
    unique (type_kind_id, meta_kind, entity),
    check (
        meta_kind not in ('NODE', 'EDGE', 'CONNECTION') and entity is null
        or entity is not null
    )
);

alter table gql.enum_value
add constraint fk_enum_value_to_type
    foreign key (type_id)
    references gql.type(id);


-- Enforce unique constraints on some special types
create unique index uq_type_meta_singleton
    on gql.type(meta_kind)
    where (meta_kind in ('QUERY', 'MUTATION', 'CURSOR', 'PAGE_INFO'));

create function gql.type_id_by_name(text)
    returns int
    language sql
as
$$ select id from gql.type where name = $1; $$;

create function gql.type_name_by_id(int)
    returns text
    language sql
as
$$ select name from gql.type where id = $1; $$;

create function gql.type_kind_id_by_value(text)
    returns int
    language sql
as
$$ select id from gql.enum_value where value = $1 and type_id = gql.type_id_by_name('__TypeKind'); $$;


create table gql.field (
    id integer generated always as identity primary key,
    -- a null parent_type_id = base level field (entrypoint)
    parent_type_id integer references gql.type(id),
    type_id integer not null references gql.type(id),
    name text not null,
    description text,
    is_not_null boolean,
    is_array boolean default false,
    is_array_not_null boolean,
    is_deprecated boolean not null default false,
    deprecation_reason text,
    is_disabled boolean default false,
    is_hidden_from_schema boolean default false,
    -- TODO trigger check column name only non-null when type is scalar
    column_name text,
    -- Relationships
    local_columns text[],
    parent_columns text[],
    -- Names must be unique on each type
    unique(parent_type_id, name),
    -- Upsert key
    unique(parent_type_id, column_name),
    -- is_array_not_null only set if is_array is true
    check (
        (not is_array and is_array_not_null is null)
        or (is_array and is_array_not_null is not null)
    ),
    -- Only column fields, total, and entrypoints can be disabled
    check (
        not is_disabled
        or column_name is not null
        or name = 'totalCount'
        -- Is an entrypoint, but not part of the required introspection system
        or (parent_type_id is null and name not in ('__type', '__schema'))
    )
);


create table gql.arg (
    id integer generated always as identity primary key,
    -- the field that accepts the argument
    field_id integer not null references gql.field(id),
    -- type of the argument
    type_id integer not null references gql.type(id),
    name text not null,
    description text,
    is_not_null boolean,
    is_array boolean default false,
    is_array_not_null boolean,
    is_deprecated boolean not null default false,
    deprecation_reason text,
    default_value text,
    -- Names must be unique on each type
    unique(field_id, name),
    check (
        (not is_array and is_array_not_null is null)
        or (is_array and is_array_not_null is not null)
    )
);


create function gql.sql_type_to_gql_type(sql_type text)
    returns int
    language sql
as
$$
    -- SQL type from information_schema.columns.data_type
    select
        case
            when sql_type like 'int%' then gql.type_id_by_name('Int')
            when sql_type like 'bool%' then gql.type_id_by_name('Boolean')
            when sql_type like 'float%' then gql.type_id_by_name('Float')
            when sql_type like 'numeric%' then gql.type_id_by_name('Float')
            when sql_type like 'json%' then gql.type_id_by_name('JSON')
            when sql_type = 'uuid' then gql.type_id_by_name('UUID')
            when sql_type like 'date%' then gql.type_id_by_name('DateTime')
            when sql_type like 'timestamp%' then gql.type_id_by_name('DateTime')
        else gql.type_id_by_name('String')
    end;
$$;


------------------------
-- Schema Translation --
------------------------

create function gql.build_schema()
    returns void
    language plpgsql
as
$$
begin
    truncate table gql.field restart identity cascade;
    truncate table gql.type restart identity  cascade;
    truncate table gql.entity restart identity cascade;

    insert into gql.entity(entity, is_disabled)
    select
        gql.to_regclass(schemaname, tablename) entity,
        false is_disabled
    from
        pg_tables pgt
    where
        schemaname not in ('information_schema', 'pg_catalog', 'gql');

    -- Populate gql.type_kind and __TypeKind because foreign keys rely on it
    set constraints all deferred;

    insert into gql.type (name, type_kind_id, meta_kind, description)
    values ('__TypeKind', 0, '__TYPE_KIND', 'An enum describing what kind of type a given `__Type` is.');

    insert into gql.enum_value(type_id, value, description)
    values
        (gql.type_id_by_name('__TypeKind'), 'SCALAR', null),
        (gql.type_id_by_name('__TypeKind'), 'OBJECT', null),
        (gql.type_id_by_name('__TypeKind'), 'INTERFACE', null),
        (gql.type_id_by_name('__TypeKind'), 'UNION', null),
        (gql.type_id_by_name('__TypeKind'), 'ENUM', null),
        (gql.type_id_by_name('__TypeKind'), 'INPUT_OBJECT', null),
        (gql.type_id_by_name('__TypeKind'), 'LIST', null),
        (gql.type_id_by_name('__TypeKind'), 'NON_NULL', null);

    update gql.type
    set type_kind_id = (select id from gql.enum_value where value = 'ENUM')
    where name = '__TypeKind';

    -- Constants
    insert into gql.type (name, type_kind_id, meta_kind, description)
    values
        ('ID', gql.type_kind_id_by_value('SCALAR'), 'BUILTIN', null),
        ('Int', gql.type_kind_id_by_value('SCALAR'), 'BUILTIN', null),
        ('Float', gql.type_kind_id_by_value('SCALAR'), 'BUILTIN', null),
        ('String', gql.type_kind_id_by_value('SCALAR'), 'BUILTIN', null),
        ('Boolean', gql.type_kind_id_by_value('SCALAR'), 'BUILTIN', null),
        ('DateTime', gql.type_kind_id_by_value('SCALAR'), 'CUSTOM_SCALAR', null),
        ('BigInt', gql.type_kind_id_by_value('SCALAR'), 'CUSTOM_SCALAR', null),
        ('UUID', gql.type_kind_id_by_value('SCALAR'), 'CUSTOM_SCALAR', null),
        ('JSON', gql.type_kind_id_by_value('SCALAR'), 'CUSTOM_SCALAR', null),
        ('Query', gql.type_kind_id_by_value('OBJECT'), 'QUERY', null),
        ('Mutation', gql.type_kind_id_by_value('OBJECT'), 'MUTATION', null),
        ('PageInfo', gql.type_kind_id_by_value('OBJECT'), 'PAGE_INFO', null),
        -- Introspection System
        ('__Schema', gql.type_kind_id_by_value('OBJECT'), '__SCHEMA', 'A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.'),
        ('__Type', gql.type_kind_id_by_value('OBJECT'), '__TYPE', 'The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the `__TypeKind` enum.\n\nDepending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional `specifiedByURL`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.'),
        ('__Field', gql.type_kind_id_by_value('OBJECT'), '__FIELD', 'Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.'),
        ('__InputValue', gql.type_kind_id_by_value('OBJECT'), '__INPUT_VALUE', 'Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.'),
        ('__EnumValue', gql.type_kind_id_by_value('OBJECT'), '__ENUM_VALUE', 'One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.'),
        ('__DirectiveLocation', gql.type_kind_id_by_value('ENUM'), '__DIRECTIVE_LOCATION', 'A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.'),
        ('__Directive', gql.type_kind_id_by_value('OBJECT'), '__DIRECTIVE', 'A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.\n\nIn some cases, you need to provide options to alter GraphQL execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.');


    insert into gql.enum_value(type_id, value, description)
    values
        (gql.type_id_by_name('__DirectiveLocation'), 'QUERY', 'Location adjacent to a query operation.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'MUTATION', 'Location adjacent to a mutation operation.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'SUBSCRIPTION', 'Location adjacent to a subscription operation.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'FIELD', 'Location adjacent to a field.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'FRAGMENT_DEFINITION', 'Location adjacent to a fragment definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'FRAGMENT_SPREAD', 'Location adjacent to a fragment spread.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'INLINE_FRAGMENT', 'Location adjacent to an inline fragment.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'VARIABLE_DEFINITION', 'Location adjacent to a variable definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'SCHEMA', 'Location adjacent to a schema definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'SCALAR', 'Location adjacent to a scalar definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'OBJECT', 'Location adjacent to an object type definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'FIELD_DEFINITION', 'Location adjacent to a field definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'ARGUMENT_DEFINITION', 'Location adjacent to an argument definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'INTERFACE', 'Location adjacent to an interface definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'UNION', 'Location adjacent to a union definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'ENUM', 'Location adjacent to an enum definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'ENUM_VALUE', 'Location adjacent to an enum value definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'INPUT_OBJECT', 'Location adjacent to an input object type definition.'),
        (gql.type_id_by_name('__DirectiveLocation'), 'INPUT_FIELD_DEFINITION', 'Location adjacent to an input object field definition.');


    insert into gql.field(parent_type_id, type_id, name, is_not_null, is_array, is_array_not_null, description)
    values
        (gql.type_id_by_name('__Schema'), gql.type_id_by_name('String'), 'description', false, false, null, null),
        (gql.type_id_by_name('__Schema'), gql.type_id_by_name('__Type'), 'types', true, true, true, 'A list of all types supported by this server.'),
        (gql.type_id_by_name('__Schema'), gql.type_id_by_name('__Type'), 'queryType', true, false, null, 'The type that query operations will be rooted at.'),
        (gql.type_id_by_name('__Schema'), gql.type_id_by_name('__Type'), 'mutationType', false, false, null, 'If this server supports mutation, the type that mutation operations will be rooted at.'),
        (gql.type_id_by_name('__Schema'), gql.type_id_by_name('__Type'), 'subscriptionType', false, false, null, 'If this server support subscription, the type that subscription operations will be rooted at.'),
        (gql.type_id_by_name('__Schema'), gql.type_id_by_name('__Directive'), 'directives', true, true, true, 'A list of all directives supported by this server.'),
        (gql.type_id_by_name('__Directive'), gql.type_id_by_name('String'), 'name', true, false, null, null),
        (gql.type_id_by_name('__Directive'), gql.type_id_by_name('String'), 'description', false, false, null, null),
        (gql.type_id_by_name('__Directive'), gql.type_id_by_name('Boolean'), 'isRepeatable', true, false, null, null),
        (gql.type_id_by_name('__Directive'), gql.type_id_by_name('__DirectiveLocation'), 'locations', true, true, true, null),
        (gql.type_id_by_name('__Directive'), gql.type_id_by_name('__InputValue'), 'args', true, true, true, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__TypeKind'), 'kind', true, false, null, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('String'), 'name', false, false, null, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('String'), 'description', false, false, null, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('String'), 'specifiedByURL', false, false, null, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__Field'), 'fields', true, true, false, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__Type'), 'interfaces', true, true, false, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__Type'), 'possibleTypes', true, true, false, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__EnumValue'), 'enumValues', true, true, false, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__InputValue'), 'inputFields', true, true, false, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__Type'), 'ofType', false, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('String'), 'name', true, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('String'), 'description', false, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('Boolean'), 'isDeprecated', true, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('String'), 'deprecationReason', false, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('__InputValue'), 'args', true, true, true, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('__Type'), 'type', true, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('String'), 'name', true, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('String'), 'description', false, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('String'), 'defaultValue', false, false, null, 'A GraphQL-formatted string representing the default value for this input value.'),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('Boolean'), 'isDeprecated', true, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('String'), 'deprecationReason', false, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('__Type'), 'type', true, false, null, null),
        (gql.type_id_by_name('__EnumValue'), gql.type_id_by_name('String'), 'name', true, false, null, null),
        (gql.type_id_by_name('__EnumValue'), gql.type_id_by_name('String'), 'description', false, false, null, null),
        (gql.type_id_by_name('__EnumValue'), gql.type_id_by_name('Boolean'), 'isDeprecated', true, false, null, null),
        (gql.type_id_by_name('__EnumValue'), gql.type_id_by_name('String'), 'deprecationReason', false, false, null, null);

    -- TODO: create a table for gql.field_argument and populate it with the the comments in the block above using the reference
    -- https://github.com/graphql/graphql-js/blob/main/src/type/introspection.ts#L252
    -- Connections and entrypoints will also need input arguments

    -- Node, Edge, and Connection Types
    insert into gql.type (name, type_kind_id, meta_kind, entity, is_disabled)
    select gql.to_pascal_case(gql.to_table_name(entity)), gql.type_kind_id_by_value('OBJECT'), 'NODE'::gql.meta_kind, entity, false from gql.entity
    union all select gql.to_pascal_case(gql.to_table_name(entity)) || 'Edge', gql.type_kind_id_by_value('OBJECT'), 'EDGE', entity, false from gql.entity
    union all select gql.to_pascal_case(gql.to_table_name(entity)) || 'Connection', gql.type_kind_id_by_value('OBJECT'), 'CONNECTION', entity, false from gql.entity;

    -- Enum Types
    insert into gql.type (name, type_kind_id, meta_kind, is_disabled)
    select
        gql.to_pascal_case(t.typname) as name,
        gql.type_kind_id_by_value('ENUM') as type_kind,
        'CUSTOM_SCALAR' as meta_kind,
        false
    from
        pg_type t
        join pg_enum e
            on t.oid = e.enumtypid
        join pg_catalog.pg_namespace n
            on n.oid = t.typnamespace
    where
        n.nspname not in ('gql', 'information_schema')
    group by
        n.nspname,
        t.typname;
    -- Enum values
    insert into gql.enum_value (type_id, value)
    select
        gql.type_id_by_name(gql.to_pascal_case(t.typname)),
        e.enumlabel as value
    from
        pg_type t
        join pg_enum e
            on t.oid = e.enumtypid
        join pg_catalog.pg_namespace n
            on n.oid = t.typnamespace
    where
        n.nspname not in ('gql', 'information_schema');



    -- PageInfo
    insert into gql.field(parent_type_id, type_id, name, is_not_null, is_array, is_array_not_null, column_name)
    values
        (gql.type_id_by_name('PageInfo'), gql.type_id_by_name('Boolean'), 'hasPreviousPage', true, false, null, null),
        (gql.type_id_by_name('PageInfo'), gql.type_id_by_name('Boolean'), 'hasNextPage', true, false, null, null),
        (gql.type_id_by_name('PageInfo'), gql.type_id_by_name('String'), 'startCursor', true, false, null, null),
        (gql.type_id_by_name('PageInfo'), gql.type_id_by_name('String'), 'endCursor', true, false, null, null);

    -- Edges
    insert into gql.field(parent_type_id, type_id, name, is_not_null, is_array, is_array_not_null, column_name)
        -- Edge.node:
        select
            edge.id parent_type_id,
            node.id type_id,
            'node' as name,
            false is_not_null,
            false is_array,
            null::boolean is_array_not_null,
            null::text as column_name
        from
            gql.type edge
            join gql.type node
                on edge.entity = node.entity
        where
            edge.meta_kind = 'EDGE'
            and node.meta_kind = 'NODE'
        union all
        -- Edge.cursor
        select
            edge.id, gql.type_id_by_name('String'), 'cursor', true, false, null, null
        from
            gql.type edge
        where
            edge.meta_kind = 'EDGE';

    -- Connection
    insert into gql.field(parent_type_id, type_id, name, is_not_null, is_array, is_array_not_null, column_name)
        -- Connection.edges:
        select
            conn.id parent_type_id,
            edge.id type_id,
            'edges' as name,
            false is_not_null,
            true is_array,
            false::boolean is_array_not_null,
            null::text as column_name
        from
            gql.type conn
            join gql.type edge
                on conn.entity = edge.entity
        where
            conn.meta_kind = 'CONNECTION'
            and edge.meta_kind = 'EDGE'
        union all
        -- Connection.pageInfo
        select conn.id, gql.type_id_by_name('PageInfo'), 'pageInfo', true, false, null, null
        from gql.type conn
        where conn.meta_kind = 'CONNECTION'
        union all
        -- Connection.totalCount (disabled by default)
        select conn.id, gql.type_id_by_name('Int'), 'totalCount', true, false, null, null
        from gql.type conn
        where conn.meta_kind = 'CONNECTION';


    -- Node
    insert into gql.field(parent_type_id, type_id, name, is_not_null, is_array, is_array_not_null, column_name)
        -- Node.<column>
        select distinct
            gt.id parent_type_id,
            case
                -- substring removes the underscore prefix from array types
                when c.data_type = 'ARRAY' then gql.sql_type_to_gql_type(substring(udt_name, 2, 100))
                else gql.sql_type_to_gql_type(c.data_type)
            end type_id,
            gql.to_camel_case(c.column_name::text) as name,
            case when c.data_type = 'ARRAY' then false else c.is_nullable = 'NO' end as is_not_null,
            case when c.data_type = 'ARRAY' then true else false end is_array,
            case when c.data_type = 'ARRAY' then c.is_nullable = 'NO' else null end is_array_not_null,
            c.column_name::text as column_name
        from
            gql.entity ent
            join gql.type gt
                on ent.entity = gt.entity
            join information_schema.role_column_grants rcg
                on ent.entity = gql.to_regclass(rcg.table_schema, rcg.table_name)
            join information_schema.columns c
                on rcg.table_schema = c.table_schema
                and rcg.table_name = c.table_name
                and rcg.column_name = c.column_name
        where
            gt.meta_kind = 'NODE'
            -- INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
            and rcg.privilege_type = 'SELECT'
            and (
                -- Use access level of current role
                rcg.grantee = current_setting('role')
                -- If superuser, allow everything
                or current_setting('role') = 'none'
            )
        union all
        -- Node.nodeId
        select distinct
            gt.id parent_type_id,
            gql.type_id_by_name('ID'),
            'nodeId',
            true,
            false,
            null::boolean,
            null::text
        from
            gql.entity ent
            join gql.type gt
                on ent.entity = gt.entity
        where
            gt.meta_kind = 'NODE';

    -- Node.<relationship>
    insert into gql.field(parent_type_id, type_id, name, is_not_null, is_array, is_array_not_null, parent_columns, local_columns)
        -- Node.<connection>
        select
            node.id parent_type_id,
            conn.id type_id,
            case
                when (
                    rel.foreign_cardinality = 'MANY'
                    and gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) not in (select name from gql.field where parent_type_id = node.id)
                ) then gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) || 's'
                else gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) || 'RequiresNameOverride'
            end,
            -- todo
            false as is_not_null,
            true as is_array,
            false as is_array_not_null, -- TODO: check this
            rel.local_columns,
            rel.foreign_columns
        from
            gql.type node
            join gql.relationship rel
                on node.entity = rel.local_entity
            join gql.type conn
                on conn.entity = rel.foreign_entity
        where
            node.meta_kind = 'NODE'
            and conn.meta_kind = 'CONNECTION'
            and rel.foreign_cardinality = 'MANY'
        union all
        -- Node.<node>
        select
            node.id parent_type_id,
            conn.id type_id,
            case
                -- owner_id -> owner
                when (
                    array_length(rel.local_columns, 1) = 1
                    and rel.local_columns[1] like '%_id'
                    and rel.foreign_cardinality = 'ONE'
                    and gql.to_camel_case(left(rel.local_columns[1], -3)) not in (select name from gql.field where parent_type_id = node.id)
                ) then gql.to_camel_case(left(rel.local_columns[1], -3))
                when (
                    rel.foreign_cardinality = 'ONE'
                    and gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) not in (select name from gql.field where parent_type_id = node.id)
                ) then gql.to_camel_case(gql.to_table_name(rel.foreign_entity))
                else gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) || 'RequiresNameOverride2'
            end,
            -- todo
            false as is_not_null,
            false as is_array,
            null as is_array_not_null,
            rel.local_columns,
            rel.foreign_columns
        from
            gql.type node
            join gql.relationship rel
                on node.entity = rel.local_entity
            join gql.type conn
                on conn.entity = rel.foreign_entity
        where
            node.meta_kind = 'NODE'
            and conn.meta_kind = 'NODE'
            and rel.foreign_cardinality = 'ONE';

    -- Resolver Entrypoints
    insert into gql.field(type_id, name, is_not_null, is_array, parent_type_id, is_hidden_from_schema)
        select gql.type_id_by_name('__Type'), '__type', true, false, gql.type_id_by_name('Query'), true
        union all
        select gql.type_id_by_name('__Schema'), '__schema', true, false, gql.type_id_by_name('Query'), true
        union all
        -- Node
        select t.id, gql.to_camel_case(gql.to_table_name(t.entity)), false, false, gql.type_id_by_name('Query'), false
        from gql.type t
        where t.meta_kind = 'NODE'
        union all
        -- Connections
        select t.id, gql.to_camel_case('all_' || gql.to_table_name(t.entity) || 's'), false, false, gql.type_id_by_name('Query'), false
        from gql.type t
        where t.meta_kind = 'CONNECTION';

    -- Every output type with fields has a __typename field
    insert into gql.field(parent_type_id, type_id, name, is_not_null, is_hidden_from_schema)
        select distinct f.parent_type_id, gql.type_id_by_name('String'), '__typename', true, true
        from gql.field f;


    -- Arguments
    insert into gql.arg(field_id, name, type_id, is_not_null, default_value)
        -- __Field(includeDeprecated)
        select f.id, 'includeDeprecated', gql.type_id_by_name('Boolean'), false, 'f'
        from gql.field f
        where
            f.type_id = gql.type_id_by_name('__Field')
            and f.is_array
        union all
        -- __enumValue(includeDeprecated)
        select f.id, 'includeDeprecated', gql.type_id_by_name('Boolean'), false, 'f'
        from gql.field f
        where
            f.type_id = gql.type_id_by_name('__enumValue')
            and f.is_array
        union all
        -- __InputFields(includeDeprecated)
        select f.id, 'includeDeprecated', gql.type_id_by_name('Boolean'), false, 'f'
        from gql.field f
        where
            f.type_id = gql.type_id_by_name('__InputFields')
            and f.is_array;


    insert into gql.arg(field_id, name, type_id, is_not_null)
        -- __type(name)
        select
            f.id field_id,
            'name' as name,
            gql.type_id_by_name('String') type_id,
            true as is_not_null
        from gql.field f
        where f.name = '__type'
        union all
        -- Node(id)
        select
            f.id field_id,
            'id' as name,
            gql.type_id_by_name('ID') type_id,
            true as is_not_null
        from
            gql.type t
            inner join gql.field f
                on t.id = f.type_id
        where
            t.meta_kind = 'NODE'
        union all
        -- Connection(first, last, after, before)
        select
            f.id field_id, y.name_ as name, gql.type_id_by_name('Int') type_id, false as is_not_null
        from
            gql.type t
            inner join gql.field f
                on t.id = f.type_id,
            --lateral (select name_ from unnest(array['first', 'last']) x(name_)) y(name_)
            lateral (select name_ from unnest(array['first']) x(name_)) y(name_)
        where t.meta_kind = 'CONNECTION'
        union all
        select
            f.id field_id, y.name_ as name, gql.type_id_by_name('String') type_id, false as is_not_null
        from
            gql.type t
            inner join gql.field f
                on t.id = f.type_id,
            --lateral (select name_ from unnest(array['before', 'after']) x(name_)) y(name_)
            lateral (select name_ from unnest(array['after']) x(name_)) y(name_)
        where t.meta_kind = 'CONNECTION'
        union all
        -- Node(nodeId)
        -- Restrict to entrypoint only?
        select
            f.id field_id, 'nodeId' as name, gql.type_id_by_name('ID') type_id, true as is_not_null
        from
            gql.type t
            inner join gql.field f
                on t.id = f.type_id
        where t.meta_kind = 'NODE';

end;
$$;


-------------
-- Resolve --
-------------


create or replace function gql.tab(n int = 1)
    returns text
    language sql
    immutable
as
$$
    select repeat(E'\t', n)
$$;





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


create or replace function gql.quote_ident(regclass)
    returns text
    language sql
    immutable
as $$
    select
        quote_ident(nspname) || '.' || quote_ident(relname)
    from
        pg_catalog.pg_class AS c
    join pg_catalog.pg_namespace AS ns
          on c.relnamespace = ns.oid
    where
        c.oid = $1;
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
    parent_type_id int = null,
    parent_block_name text = null,
    indent_level int = 0
)
    returns text
    language sql
as $$
    with b as (
        select gql.slug() as block_name
    ),
    field as (
        select * from gql.field gf where gf.name = gql.name(ast) and gf.parent_type_id = $4
    ),
    type_ as (
        select * from gql.type gt where gt.id = (select type_id from field)
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
                on ga.field_id = field.id
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
                    parent_type_id := gf.type_id,
                    parent_block_name := b.block_name,
                    indent_level := indent_level + 1
                )
                when nf.local_columns is not null then gql.build_node_query(
                    ast := x.sel,
                    variables := variables,
                    variable_definitions := variable_definitions,
                    parent_type_id := gf.type_id,
                    parent_block_name := b.block_name,
                    indent_level := indent_level + 1
                )
                else null::text
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
    gql.quote_ident(gt.entity),
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
            on nf.parent_type_id = gf.type_id
            and gql.name(x.sel) = nf.name,
        b
    where
        gf.name = gql.name(ast)
        and $4 = gf.parent_type_id
    group by
        gt.entity, b.block_name, gf.parent_columns, gf.local_columns, args.pkey_safe
$$;




create or replace function gql.build_connection_query(
    ast jsonb,
    variables jsonb = '{}',
    variable_definitions jsonb = '[]',
    parent_type_id int = null,
    parent_block_name text = null,
    indent_level int = 0
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
            on f.type_id = t.id
    where
        f.name = gql.name(ast)
        and f.parent_type_id = $4
),
root(sel) as (select * from jsonb_array_elements(ast -> 'selectionSet' -> 'selections')),
field_row as (select * from gql.field f where f.name = gql.name(ast) and f.parent_type_id = $4),
total_count(sel, q) as (select root.sel, format('%L, coalesce(min(%I.%I), 0)', gql.alias_or_name(root.sel), b.block_name, '__total_count')  from root, b where gql.name(sel) = 'totalCount'),
args as (
    select
        min(case when gql.name(sel) = 'first' then coalesce(ar.sel -> 'value' ->> 'value') else null end) as first_val,
        min(null::text) as last_val
    from
        jsonb_array_elements(case when jsonb_typeof(ast -> 'arguments') = 'array' then ast -> 'arguments' else '[]' end ) ar(sel)
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
                                                                                    parent_type_id := gf_n.type_id,
                                                                                    parent_block_name := b.block_name,
                                                                                    indent_level := 0
                                                                                )
                                when gf_s.local_columns is not null and gf_s.is_array then gql.build_connection_query(
                                                                                    ast := n.sel,
                                                                                    variables := variables,
                                                                                    variable_definitions := variable_definitions,
                                                                                    parent_type_id := gf_n.type_id,
                                                                                    parent_block_name := b.block_name,
                                                                                    indent_level := 0
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
                 on gf_c.type_id = gf_e.parent_type_id
                 and gf_e.name = 'edges'
            join gql.field gf_n -- node field
                 on gf_e.type_id = gf_n.parent_type_id
                 and gf_n.name = 'node'
             join gql.field gf_s -- node selections
                 on gf_n.type_id = gf_s.parent_type_id
                 and gql.name(n.sel) = gf_s.name
             join gql.type gt_s -- node selection type
                 on gf_n.type_id = gt_s.id
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
            %s as %s
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
        gql.quote_ident(entity),
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






create or replace function gql."resolve_enumValues"(type_id int, ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select jsonb_agg(
        jsonb_build_object(
            'description', value::text,
            'deprecationReason', null
        )
        order by id asc)
    from
        gql.enum_value ev where ev.type_id = $1;
$$;


-- stubs for recursion
create or replace function gql.resolve___input_value(arg_id int, ast jsonb) returns jsonb language sql as $$ select 'STUB'::text::jsonb $$;
create or replace function gql."resolve___Type"(
    type_id int,
    ast jsonb,
    is_array_not_null bool = false,
    is_array bool = false,
    is_not_null bool = false
) returns jsonb language sql as $$ select 'STUB'::text::jsonb $$;
create or replace function gql.resolve_field(field_id int, ast jsonb) returns jsonb language sql as $$ select 'STUB'::text::jsonb $$;


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
                    when selection_name = 'type' then gql."resolve___Type"(ar.type_id, x.sel)
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


create or replace function gql.resolve_field(field_id int, ast jsonb)
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
                    when selection_name = 'isDeprecated' then to_jsonb(f.is_deprecated)
                    when selection_name = 'deprecationReason' then to_jsonb(f.deprecation_reason)
                    when selection_name = 'type' then gql."resolve___Type"(f.type_id, x.sel, f.is_array_not_null, f.is_array, f.is_not_null)
                    when selection_name = 'args' then '[]'::jsonb --gql."resolve___InputValues"(f.type_id, x.sel, f.is_array_not_null, f.is_array, f.is_not_null)
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
            on f.id = field_id
$$;




create or replace function gql."resolve___Type"(type_id int, ast jsonb, is_array_not_null bool = false, is_array bool = false, is_not_null bool = false)
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
                            else to_jsonb((select value::text from gql.enum_value where id = gt.type_kind_id limit 1))
                            --else to_jsonb('OTHER'::text)
                        end
                    )
                    when selection_name = 'fields' and not has_modifiers then (
                        case
                            -- TODO, un-hardcode
                            when gt.name = 'Mutation' then '[]'::jsonb
                            else (select jsonb_agg(gql.resolve_field(f.id, x.sel)) from gql.field f where f.parent_type_id = gt.id and not f.is_hidden_from_schema)
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
                    when selection_name = 'enumValues' then gql."resolve_enumValues"(gt.id, x.sel)
                    when selection_name = 'inputFields' and not has_modifiers then to_jsonb(null::text)
                    when selection_name = 'ofType' then (
                        case
                            -- NON_NULL(LIST(...))
                            when is_array_not_null is true then gql."resolve___Type"(type_id, x.sel, is_array_not_null := false, is_array := is_array, is_not_null := is_not_null)
                            -- LIST(...)
                            when is_array then gql."resolve___Type"(type_id, x.sel, is_array_not_null := false, is_array := false, is_not_null := is_not_null)
                            -- NON_NULL(...)
                            when is_not_null then gql."resolve___Type"(type_id, x.sel, is_array_not_null := false, is_array := false, is_not_null := false)
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
        gt.id = type_id
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
    variable_definitions jsonb = '[]',
    indent_level int = 0
)
    returns text
    stable
    language plpgsql
    as $$
declare
    node_fields jsonb = jsonb_path_query(ast, '$.selectionSet.selections');
    node_field jsonb;
    node_field_rec gql.field;
    agg jsonb = '{}';
begin
    --field_rec = "field" from gql.field where parent_type_id = gql.type_id_by_name('__Schema') and name = field_name;

    for node_field in select * from jsonb_array_elements(node_fields) loop
        node_field_rec = "field" from gql.field where parent_type_id = gql.type_id_by_name('__Schema') and name = gql.name(node_field);

        if gql.name(node_field) = 'description' then
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), node_field_rec.description);
        elsif node_field_rec.type_id = gql.type_id_by_name('__Directive') then
            -- TODO
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), '[]'::jsonb);

        elsif node_field_rec.name = 'queryType' then
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), gql."resolve_queryType"(node_field));

        elsif node_field_rec.name = 'mutationType' then
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), gql."resolve_mutationType"(node_field));

        elsif node_field_rec.name = 'subscriptionType' then
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), null);

        elsif node_field_rec.name = 'types' then
            agg = agg || jsonb_build_object(gql.alias_or_name(node_field), jsonb_agg(gql."resolve___Type"(gt.id, node_field))) from gql.type gt;


        elsif node_field_rec.type_id = gql.type_id_by_name('__Type') and not node_field_rec.is_array then
            agg = agg || gql."resolve___Type"(
                node_field_rec.type_id,
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

    -- Variable Definitions (deterministic sorted)
    variable_definitions jsonb = (
        select
            jsonb_agg(jae.f order by jae.f -> 'variable' -> 'name' ->> 'value' asc)
        from
            jsonb_array_elements(
                case jsonb_typeof(ast -> 'definitions' -> 0 -> 'variableDefinitions')
                    when 'array' then ast -> 'definitions' -> 0 -> 'variableDefinitions'
                    else to_jsonb('{}'::text[])
                end
            ) jae(f)
    );

    prep_statement_exec text;
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
    -- Call prepared statement respecting passed values and variable definition defaults
    select
        case count(1)
            when 0 then format('execute %I', prepared_statement_name)
            else
                format('execute %I (', prepared_statement_name)
                || string_agg(format('%L', coalesce(var.val, def ->> 'defaultValue')), ',' order by def_idx)
                || ')'
        end
    from
        jsonb_array_elements(variable_definitions) with ordinality d(def, def_idx)
        left join jsonb_each_text(variables) var(key_, val)
            on gql.name(def -> 'variable') = var.key_
    into prep_statement_exec;

    raise notice 'prep_statment_exec %s', prep_statement_exec;

    -- Check cache
    if exists(select 1 from pg_prepared_statements where name = prepared_statement_name) then

        execute prep_statement_exec into data_;


        data_ = jsonb_build_object(
            gql.name(ast -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0),
            data_
        );

        raise notice 'data %', data_;

        return jsonb_build_object(
            'data', data_,
            'errors', to_jsonb(errors_)
        );
    end if;

    -- Didn't exist in cache
    ast_locless = gql.ast_pass_strip_loc(ast);
    fragment_definitions = jsonb_path_query_array(ast_locless, '$.definitions[*] ? (@.kind == "FragmentDefinition")');
    ast_inlined =  gql.ast_pass_fragments(ast_locless, fragment_definitions);
    ast_operation = ast_inlined -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0;
    meta_kind = type_.meta_kind from gql.field join gql.type type_ on field.type_id = type_.id
                where field.parent_type_id = gql.type_id_by_name('Query') and field.name = gql.name(ast_operation);

    if meta_kind ='CONNECTION' then
        -- Check top type. Default connection
        q = gql.build_connection_query(
            ast := ast_operation,
            variables := variables,
            variable_definitions := variable_definitions,
            parent_type_id :=  gql.type_id_by_name('Query'),
            parent_block_name := null,
            indent_level := 0
        );
        execute q into data_;
        data_ = jsonb_build_object(
            gql.name(ast_operation),
            data_
        );

    elsif meta_kind ='NODE' then
        q = gql.build_node_query(
            ast := ast_operation,
            variables := variables,
            variable_definitions := variable_definitions,
            parent_type_id := gql.type_id_by_name('Query'),
            parent_block_name := null,
            indent_level := 0
        );
        raise notice 'Query %s', q;

        -- Create Prepared Statement
        execute format(
            'prepare %I %s as %s',
            prepared_statement_name,
            case jsonb_array_length(variable_definitions)
                when 0 then ''
                else (select '(' || string_agg('text', ', ') || ')' from jsonb_array_elements(variable_definitions) jae(vd))
            end,
            q
        );

        execute prep_statement_exec into data_;

        data_ = jsonb_build_object(
            gql.name(ast_operation),
            data_
        );

    elsif meta_kind ='__SCHEMA' then
        data_ = gql."resolve___Schema"(
            ast := ast_operation,
            variables := variables,
            variable_definitions := variable_definitions
         );

    elsif meta_kind ='__TYPE' then
        data_ = jsonb_build_object(
            gql.name(ast_operation),
            gql."resolve___Type"(
                (select id from gql.type where name = gql.argument_value_by_name('name', ast_operation)),
                ast_operation
            )
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
