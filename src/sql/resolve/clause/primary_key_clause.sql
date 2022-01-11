create or replace function graphql.primary_key_clause(entity regclass, alias_name text)
    returns text
    language sql
    immutable
    as
$$
    select '(' || string_agg(quote_ident(alias_name) || '.' || quote_ident(x), ',') ||')'
    from unnest(graphql.primary_key_columns(entity)) pk(x)
$$;
