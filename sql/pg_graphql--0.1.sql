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

create type gql.type_type as enum('Scalar', 'Node', 'Edge', 'Connection', 'PageInfo', 'Object', 'Enum');

create table gql.type (
	id integer generated always as identity primary key,
	name text not null unique,
	type_type gql.type_type not null,
	entity regclass references gql.entity(entity),
	is_disabled boolean not null default false,
	is_builtin boolean not null default false,
	enum_variants text[],
    check (
        type_type != 'Enum' and enum_variants is null
        or type_type = 'Enum' and enum_variants is not null
    ),
	unique (type_type, entity)
);


create function gql.type_id_by_name(text)
	returns int
	language sql
as
$$ select id from gql.type where name = $1; $$;

create table gql.field (
	id integer generated always as identity primary key,
	parent_type_id integer not null references gql.type(id),
	type_id integer not null references gql.type(id),
	name text not null,
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
	truncate table gql.field cascade;
	truncate table gql.type cascade;
	truncate table gql.entity cascade;

	insert into gql.entity(entity, is_disabled)
	select
		gql.to_regclass(schemaname, tablename) entity,
		false is_disabled
	from
		pg_tables pgt
	where
		schemaname not in ('information_schema', 'pg_catalog', 'gql');


	-- Constants
	insert into gql.type (name, type_type, is_builtin)
	values
		('ID', 'Scalar', true),
		('Int', 'Scalar', true),
		('Float', 'Scalar', true),
		('String', 'Scalar', true),
		('Boolean', 'Scalar', true),
		('DateTime', 'Scalar', false),
		('BigInt', 'Scalar', false),
		('UUID', 'Scalar', false),
		('JSON', 'Scalar', false),
		('Query', 'Object', false),
		('Mutation', 'Object', false),
		('PageInfo', 'PageInfo', false);
	-- Node Types
	-- TODO snake case to camel case to handle underscores
	insert into gql.type (name, type_type, entity, is_disabled, is_builtin)
	select gql.to_pascal_case(gql.to_table_name(entity)), 'Node',	entity,	false, false
	from gql.entity;
	-- Edge Types
	insert into gql.type (name, type_type, entity, is_disabled, is_builtin)
	select gql.to_pascal_case(gql.to_table_name(entity)) || 'Edge', 'Edge',	entity,	false, false
	from gql.entity;
	-- Connection Types
	insert into gql.type (name, type_type, entity, is_disabled, is_builtin)
	select gql.to_pascal_case(gql.to_table_name(entity)) || 'Connection', 'Connection',	entity,	false, false
	from gql.entity;

    -- Enum Types
	insert into gql.type (name, type_type, is_disabled, is_builtin, enum_variants)
    select
        gql.to_pascal_case(t.typname) as name,
        'Enum' as type_type,
        false,
        false,
        array_agg(e.enumlabel) as enum_value
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
			edge.type_type = 'Edge'
			and node.type_type = 'Node'
		union all
		-- Edge.cursor
		select
			edge.id, gql.type_id_by_name('String'), 'cursor', true, false, null, null
		from
			gql.type edge
		where
			edge.type_type = 'Edge';

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
			conn.type_type = 'Connection'
			and edge.type_type = 'Edge'
		union all
		-- Connection.pageInfo
		select conn.id, gql.type_id_by_name('PageInfo'), 'pageInfo', true, false, null, null
		from gql.type conn
		where conn.type_type = 'Connection'
		union all
		-- Connection.totalCount (disabled by default)
		select conn.id, gql.type_id_by_name('Int'), 'totalCount', true, false, null, null
		from gql.type conn
		where conn.type_type = 'Connection';


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
			gt.type_type = 'Node'
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
			node.type_type = 'Node'
			and conn.type_type = 'Connection'
		order by
			rel.local_entity, local_columns;
end;
$$;


grant all on schema gql to postgres;
grant all on all tables in schema gql to postgres;

