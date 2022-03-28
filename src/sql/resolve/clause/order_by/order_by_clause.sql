create or replace function graphql.order_by_clause(
    alias_name text,
    column_orders graphql.column_order_w_type[]
)
    returns text
    language sql
    immutable
    as
$$
    select
        string_agg(
            format(
                '%I.%I %s %s',
                alias_name,
                (co).column_name,
                (co).direction::text,
                case
                    when (co).nulls_first then 'nulls first'
                    else 'nulls last'
                end
            ),
            ', '
        )
    from
        unnest(column_orders) co
$$;
