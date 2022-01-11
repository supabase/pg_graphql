create or replace function graphql.prepared_statement_exists(statement_name text)
    returns boolean
    language sql
    stable
as $$
    select exists(select 1 from pg_prepared_statements where name = statement_name)
$$;
