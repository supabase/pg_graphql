create or replace function graphql.cursor_clause_for_literal(cursor_ text)
    returns text
    language sql
    immutable
    as
$$
    -- SQL string
    -- Example:
    --        select graphql.cursor_clause_for_literal('WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd')
    --        row('public','account','2')
    -- Note:
    --         Type casts are not necessary because the values are visible to the planner allowing coercion
    select 'row(' || string_agg(quote_literal(x), ',') || ')'
    from jsonb_array_elements_text(convert_from(decode(cursor_, 'base64'), 'utf-8')::jsonb) y(x)
$$;
