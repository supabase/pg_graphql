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
