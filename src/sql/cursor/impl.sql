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
    select
        case
            when array_length(column_orders, 1) > (depth_ - 1) then format(
                '((%I.%I %s %s) or ((%I.%I = %s) and %s))',
                block_name,
                column_orders[depth_].column_name,
                case when column_orders[depth_].direction = 'asc' then '>' else '<' end,
                format(
                    '((graphql.decode(%s)) ->> %s)::%s',
                    case
                        when cursor_ is not null then format('%L', cursor_)
                        when cursor_var_ix is not null then format('$%s', cursor_var_ix)
                        -- both are null
                        else 'null'
                    end,
                    depth_ - 1,
                    (column_orders[depth_]).type_
                ),
                block_name,
                column_orders[depth_].column_name,
                format(
                    '((graphql.decode(%s)) ->> %s)::%s',
                    case
                        when cursor_ is not null then format('%L', cursor_)
                        when cursor_var_ix is not null then format('$%s', cursor_var_ix)
                        -- both are null
                        else 'null'
                    end,
                    depth_ - 1,
                    (column_orders[depth_]).type_
                ),
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
end;
$$;
