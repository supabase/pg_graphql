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






grant all on schema gql to postgres;
grant all on all tables in schema gql to postgres;










/*

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


-- Tables
create table gql.entity (
	--id integer generated always as identity primary key,
	entity regclass primary key,
	is_disabled boolean default false
);

-- Populate gql.entity
insert into gql.entity(entity, is_disabled)
select
	gql.to_regclass(schemaname, tablename) entity,
	false is_disabled
from
	pg_tables pgt
where
	schemaname not in ('information_schema', 'pg_catalog', 'gql');
	

create type gql.type_type as enum('Scalar', 'Node', 'Edge', 'Connection', 'PageInfo', 'Object');

create table gql.type (
	id integer generated always as identity primary key,
	name text not null unique,
	type_type gql.type_type not null,
	entity regclass references gql.entity(entity),
	is_disabled boolean not null default false,
	-- Does the type need to be in the schema?
	is_builtin boolean not null default false,
	unique (type_type, entity)
);

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
	-- TODO trigger check column name only non-null when type is scalar
	column_name text,
	-- Names must be unique on each type
	unique(type_id, name),
	-- is_array_not_null only set if is_array is true
	check (
		(not is_array and is_array_not_null is null)
		or (is_array and is_array_not_null is not null)
	)
);
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
		edge.id, node.id, 'node', false, false, null::boolean, null::text
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
		conn.id, edge.id, 'edges', false, true, false::boolean, null::text
	from
		gql.type conn
		join gql.type edge
			on conn.entity = edge.entity
	where
		conn.type_type = 'Connection'
		and edge.type_type = 'Edge'
	union all
	-- Connection.pageInfo
	select
		conn.id, gql.type_id_by_name('PageInfo'), 'pageInfo', true, false, null, null
	from
		gql.type conn
	where
		conn.type_type = 'Connection';



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



-- Node
insert into gql.field(parent_type_id, type_id, name, is_not_null, is_array, is_array_not_null, column_name)
	-- Node.<column>
    select
		gt.id,
		c.data_type,
		-- TODO check for pkey and int/bigint/uuid type => 'ID!'
		case
			-- substring removes the underscore prefix from array types
			when c.data_type = 'ARRAY' then gql.sql_type_to_gql_type(substring(udt_name, 2, 100))
			else gql.sql_type_to_gql_type(c.data_type)
		end,
		ent.entity,
		gt.name,
		gt.id,
		c.*
    from
		gql.entity ent
		join gql.type gt
			on ent.entity = gt.entity
        join information_schema.role_column_grants rcg
			on ent.entity = gql.to_regclass(rcg.table_schema, rcg.table_name)
        join information_schema.columns c
            on rcg.table_schema = c.table_schema
            and rcg.table_name = c.table_name
            and rcg.column_name = c.column_name,
		left join pg_index pgi
			on ent.entity = pgi.oid
		, pg_class, pg_attribute, pg_namespace
		
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
*/

