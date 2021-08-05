create schema if not exists gql;

create or replace function gql.sql_to_ast(text) returns text
as 'pg_graphql'
language C strict;


create or replace function gql.parse(text) returns text
as 'pg_graphql'
language C strict;


grant all on schema gql to postgres;
grant all on all tables in schema gql to postgres;
