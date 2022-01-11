create or replace function graphql.cursor_clause_for_variable(entity regclass, variable_idx int)
    returns text
    language sql
    immutable
    strict
as $$
    -- SQL string to decode a cursor and convert it to a record for equality or pagination
    -- Example:
    --        select graphql.cursor_clause_for_variable('public.account', 1)
    --        row(graphql.cursor_decode($1)::text, graphql.cursor_decode($1)::text, graphql.cursor_decode($1)::integer)
    select
        'row(' || string_agg(format('(graphql.cursor_decode($%s) ->> %s)::%s', variable_idx, ctype.idx-1, ctype.val), ', ') || ')'
    from
        unnest(array['text'::regtype] || graphql.primary_key_types(entity)) with ordinality ctype(val, idx);
$$;
