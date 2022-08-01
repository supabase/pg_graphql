create or replace function graphql.cache_key_variable_component(
    variables jsonb = '{}',
    variable_definitions jsonb = '[]'
)
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
    with dynamic_elems(var_name) as (
        select
           graphql.name_literal(elem -> 'variable') -- the variable's name
        from
            jsonb_array_elements(variable_definitions) with ordinality ar(elem, idx)
        where
            -- Everything other than cursors must be static
            elem::text like '%Cursor%'
    ),
    doc as (
        select
            ar.var_name || ':' || ar.var_value
        from
            jsonb_each_text(variables) ar(var_name, var_value)
            left join dynamic_elems se
                on ar.var_name = se.var_name
        where
            se.var_name is null
    )
    select
        coalesce(string_agg(y.x, ',' order by y.x), '')
    from
        doc y(x)
$$;
