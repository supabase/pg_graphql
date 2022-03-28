create type graphql.column_order_direction as enum ('asc', 'desc');


create type graphql.column_order as(
    column_name text,
    direction graphql.column_order_direction,
    nulls_first bool
);


create type graphql.cursor as (
    order_by graphql.column_order[],
    vals jsonb -- array of values
);


create or replace function graphql.to_cursor_clause(
    alias_name text,
    column_orders graphql.column_order[]
)
    returns text
    immutable
    language sql
as $$
/*
    -- Produces the SQL to create a cursor
    select graphql.to_cursor_clause(
        'abc',
        array[('email', 'asc', true), ('id', 'asc', false)]::graphql.column_order[]
    )
*/
    select
        format(
            '(
                ''%s''::graphql.column_order[],
                jsonb_build_array(%s)
            )::graphql.cursor',
            column_orders,
            (
                string_agg(
                    format(
                        'to_jsonb(%I.%I)',
                        alias_name,
                        co.elems
                    ),
                    ', '
                    order by co_ix
                )
            )
        )
    from
        unnest(column_orders) with ordinality co(elems, co_ix)
$$;


create or replace function graphql.encode(graphql.cursor)
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
    returns graphql.cursor
    language sql
    immutable
as $$
/*
    select graphql.decode(graphql.encode('("{""(email,asc,t)"",""(id,asc,f)""}","[""aardvark@x.com"", 1]")'::graphql.cursor))
*/
    select convert_from(decode($1, 'base64'), 'utf-8')::graphql.cursor
$$;
