create or replace function graphql.sha1(text)
    returns text
    strict
    immutable
    language sql
as $$
    select encode(digest($1, 'sha1'), 'hex')
$$;
