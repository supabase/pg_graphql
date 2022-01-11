create or replace function graphql.cursor_encoded_clause(entity regclass, alias_name text)
    returns text
    language sql
    immutable
    as
$$
    -- SQL string returning encoded cursor for an aliased table
    -- Example:
    --        select graphql.cursor_encoded_clause('public.account', 'abcxyz')
    --        graphql.cursor_encode(jsonb_build_array('public', 'account', abcxyz.id))
    select
        'graphql.cursor_encode(jsonb_build_array('
        || format('%L::text,', quote_ident(entity::text))
        || string_agg(quote_ident(alias_name) || '.' || quote_ident(x), ',')
        ||'))'
    from unnest(graphql.primary_key_columns(entity)) pk(x)
$$;
