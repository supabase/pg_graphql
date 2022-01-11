create or replace function graphql.slug()
    returns text
    language sql
    volatile
as $$
    select substr(md5(random()::text), 0, 12);
$$;
