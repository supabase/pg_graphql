create schema if not exists gql;


create function gql._parse(text)
returns text
language c
strict
as 'pg_graphql';


create function gql._recursive_strip_key(body jsonb, key text default 'loc')
returns jsonb
language sql
immutable
as $$
/*
Recursively remove a key from a jsonb object by name
*/
    select
        case
            when jsonb_typeof(body) = 'object' then
                (
                    select
                        jsonb_object_agg(key_, gql._recursive_strip_key(value_))
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
                        jsonb_agg(gql._recursive_strip_key(value_))
                    from
                        jsonb_array_elements(body) x(value_)
                    limit
                        1
                )
            else
                body
        end;
$$;


create function gql.parse(query text)
returns jsonb
language sql
strict
as $$
/*
{
  "kind": "Document",
  "definitions": [
    {
      "kind": "OperationDefinition",
      "name": null,
      "operation": "query",
      "directives": null,
      "selectionSet": {
        "kind": "SelectionSet",
        "selections": [
          {
            "kind": "Field",
            "name": {
              "kind": "Name",
              "value": "account"
            },
            "alias": null,
            "arguments": null,
            "directives": null,
            "selectionSet": {
              "kind": "SelectionSet",
              "selections": [
                {
                  "kind": "Field",
                  "name": {
                    "kind": "Name",
                    "value": "name"
                  },
                  "alias": null,
                  "arguments": null,
                  "directives": null,
                  "selectionSet": null
                }
              ]
            }
          }
        ]
      },
      "variableDefinitions": null
    }
  ]
}
*/
    select
        gql._recursive_strip_key(
            body:=gql._parse(query)::jsonb,
            key:='loc'
        );
$$;


create function gql.get_name(selection jsonb)
returns text
language sql
immutable
as $$
/*
{
  "kind": "Field",
  "name": {
    "kind": "Name",
    "value": "name"
  },
  "alias": null,
  "arguments": null,
  "directives": null,
  "selectionSet": null
}
*/
    select selection -> 'name' ->> 'value';
$$;

create function gql.get_alias(selection jsonb)
returns text
language sql
immutable
as $$
/*
{
  "kind": "Field",
  "name": {
    "kind": "Name",
    "value": "name"
  },
  "alias": null,
  "arguments": null,
  "directives": null,
  "selectionSet": null
}
*/
    select
        coalesce(
            selection -> 'alias' ->> 'value',
            selection -> 'name' ->> 'value'
        );
$$;




create function gql.execute(query text)
returns jsonb
language plpgsql
as $$
declare
    ast jsonb;
    -- AST for the first OperationDescription
    ast_op jsonb;
    ast_op_kind text;

    sql_template text;

    -- Operation
    operation text;

    -- Selection Set
    selection_set jsonb;
    selection jsonb;

    -- Selection
    kind text;
    name_kind text;
    name_value text;
    alias text;

    -- Extracted from arguments
    filters jsonb;

    arguments jsonb;
    argument jsonb;
    argument_name text;
    argument_value text;

    fields jsonb;
    field jsonb;
    field_col text;
    field_alias text;


    query_stmt text;
    table_name text;
    result_alias text;
    column_names text[];
    where_clause text = '';
    select_clause text = '';

    -- Reusable working index
    work_ix int;

    result jsonb;

begin

    ast = gql.parse(query);


    ast_op = ast -> 'definitions' -> 0;
    ast_op_kind = ast_op ->> 'operation';

    -- TODO: AST Pass Fragments
    -- TODO: AST Pass Variable Substitution
    -- TODO: AST Pass Directives
    -- TODO: Configurable schema
    -- TODO: Mutations

    if ast_op_kind <> 'query' then
        return '{"error": "Not Implemented: 1"}';
    end if;


    selection_set = ast_op -> 'selectionSet' -> 'selections';

    for
        selection in select * from jsonb_array_elements(selection_set)
    loop
        /*
        kind = selection ->> 'kind';
        name_kind = selection -> 'name' ->> 'kind';
        -- Table name
        -- TODO sanitize


        */

        result_alias = gql.get_alias(selection);
        table_name = gql.get_name(selection);

        ------------
        -- SELECT --
        ------------
        fields = selection -> 'selectionSet' -> 'selections';
        select_clause = '';
        work_ix = 0;
        for
            field in select * from jsonb_array_elements(fields)
        loop
            work_ix = work_ix + 1;

            -- Comma separate columns
            if work_ix > 1 then
                select_clause = select_clause || ', ';
            end if;

            field_col = field -> 'name' ->> 'value';
            field_alias = field -> 'alias' ->> 'value';

            select_clause = (
                select_clause
                || quote_ident(field_col)
                || ' as '
                || coalesce(quote_ident(field_alias), quote_ident(field_col))
            );
        end loop;

        -----------
        -- WHERE --
        -----------
        arguments = selection -> 'arguments';
        where_clause = 'true';
        work_ix = 0;
        for
            argument in select * from jsonb_array_elements(arguments)
        loop
            -- AND separate columns
            argument_name = argument -> 'name' ->> 'value';
            -- values are always represented as strings
            -- pg will coerce them automatically
            argument_value = argument -> 'value' ->> 'value';
            where_clause = (
                where_clause
                || ' and '
                ||  quote_ident(argument_name)
                || '='
                || quote_literal(argument_value)
            );
        end loop;

        execute $c$
            with rec as (
                select $c$ || select_clause           || $c$
                from $c$   || quote_ident(table_name) || $c$
                where $c$  || where_clause            || $c$
                limit 100
            )
            select
                row_to_json(rec)::jsonb
            from
                rec
            $c$
            into result;

    end loop;

    return jsonb_build_object(
        'data',
        jsonb_build_object(
            coalesce(result_alias, table_name),
            result
        )
    )

        ;
end;
$$;





create type gql.cardinality as enum ('ONE', 'MANY');


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


create function gql.to_pkey_column_names(regclass)
    returns text[]
    language sql
    stable
as
$$
    select
        coalesce(array_agg(pga.attname), '{}')
    from
        pg_index i
        join pg_attribute pga
            on pga.attrelid = i.indrelid
            and pga.attnum = any(i.indkey)
    where
        i.indrelid = $1::regclass
        and i.indisprimary;
$$;


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
    'CURSOR', 'QUERY', 'MUTATION', 'BUILTIN',
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
    is_disabled boolean not null default false,
    unique (type_kind_id, meta_kind, entity)
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

create function gql.type_kind_id_by_value(text)
    returns int
    language sql
as
$$ select id from gql.enum_value where value = $1 and type_id = gql.type_id_by_name('__TypeKind'); $$;


create table gql.field (
    id integer generated always as identity primary key,
    parent_type_id integer not null references gql.type(id),
    type_id integer not null references gql.type(id),
    name text not null,
    description text,
    is_not_null boolean,
    is_array boolean default false,
    is_array_not_null boolean,
    is_disabled boolean default false,
    -- TODO trigger check column name only non-null when type is scalar
    column_name text,
    -- Relationships
    local_columns text[],
    foreign_columns text[],
    -- Names must be unique on each type
    unique(parent_type_id, name),
    -- Upsert key
    unique(parent_type_id, column_name),
    -- is_array_not_null only set if is_array is true
    check (
        (not is_array and is_array_not_null is null)
        or (is_array and is_array_not_null is not null)
    ),
    -- Only column fields and total can be disabled
    check (
        not is_disabled
        or column_name is not null
        or name = 'totalCount'
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
        (gql.type_id_by_name('__Schema'), gql.type_id_by_name('__Type'), 'directives', true, true, true, 'A list of all directives supported by this server.'),
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
        -- fields takes args https://github.com/graphql/graphql-js/blob/main/src/type/introspection.ts#L252
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__Type'), 'interfaces', true, true, false, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__Type'), 'possibleTypes', true, true, false, null),
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__EnumValue'), 'enumValues', true, true, false, null),
        -- enumValues takes args
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__InputValue'), 'inputFields', true, true, false, null),
        -- inputFields takes args
        (gql.type_id_by_name('__Type'), gql.type_id_by_name('__Type'), 'ofType', false, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('String'), 'name', true, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('String'), 'description', false, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('__InputValue'), 'args', true, true, true, null),
        -- args takes args
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('__Type'), 'type', true, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('Boolean'), 'isDeprecated', true, false, null, null),
        (gql.type_id_by_name('__Field'), gql.type_id_by_name('String'), 'deprecationReason', false, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('String'), 'name', true, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('String'), 'description', false, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('__Type'), 'type', true, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('String'), 'defaultValue', false, false, null, 'A GraphQL-formatted string representing the default value for this input value.'),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('Boolean'), 'isDeprecated', true, false, null, null),
        (gql.type_id_by_name('__InputValue'), gql.type_id_by_name('String'), 'deprecationReason', false, false, null, null),
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
        select
            gt.id parent_type_id,
            case
                -- Detect ID! types using pkey info, restricted by types
                when c.column_name = 'id' and array[c.column_name::text] = gql.to_pkey_column_names(ent.entity)
                then gql.type_id_by_name('ID')
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
        order by
            ent.entity, c.ordinal_position;

    -- Node
    insert into gql.field(parent_type_id, type_id, name, is_not_null, is_array, is_array_not_null, local_columns, foreign_columns)
        -- Node.<connection>
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
                when (
                    rel.foreign_cardinality = 'MANY'
                    and gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) not in (select name from gql.field where parent_type_id = node.id)
                ) then gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) || 's'
                else gql.to_camel_case(gql.to_table_name(rel.foreign_entity)) || 'RequiresNameOverride'
            end,
            -- todo
            false as is_not_null,
            case
                when rel.foreign_cardinality = 'MANY' then true
                else false
            end as is_array,
            case
                when rel.foreign_cardinality = 'MANY' then false
                else null
            end as is_array_not_null,
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
        order by
            rel.local_entity, local_columns;
end;
$$;


grant all on schema gql to postgres;
grant all on all tables in schema gql to postgres;
