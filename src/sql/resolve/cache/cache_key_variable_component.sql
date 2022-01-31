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
    general_structure as (
        select
            jpath::text as x
        from
            doc
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
        coalesce(string_agg(y.x, ',' order by y.x), '')
    from
        (
            select x from general_structure
            union all
            select x from order_clause
        ) y(x)
$$;
