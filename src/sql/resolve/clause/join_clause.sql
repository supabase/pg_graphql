create or replace function graphql.join_clause(local_columns text[], local_alias_name text, parent_columns text[], parent_alias_name text)
    returns text
    language sql
    immutable
    as
$$
    select string_agg(quote_ident(local_alias_name) || '.' || quote_ident(x) || ' = ' || quote_ident(parent_alias_name) || '.' || quote_ident(y), ' and ')
    from
        unnest(local_columns) with ordinality local_(x, ix),
        unnest(parent_columns) with ordinality parent_(y, iy)
    where
        ix = iy
$$;
