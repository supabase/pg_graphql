create or replace function graphql.cursor_row_clause(entity regclass, alias_name text)
    returns text
    language sql
    immutable
    as
$$
    -- SQL string returning decoded cursor for an aliased table
    -- Example:
    --        select graphql.cursor_row_clause('public.account', 'abcxyz')
    --        row('public', 'account', abcxyz.id)
    select
        'row('
        || format('%L::text,', quote_ident(entity::text))
        || string_agg(quote_ident(alias_name) || '.' || quote_ident(x), ',')
        ||')'
    from unnest(graphql.primary_key_columns(entity)) pk(x)
$$;
