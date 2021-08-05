create schema if not exists net;

create or replace function net.sql_to_ast(text) returns text
as 'pg_net'
language C strict;


create or replace function net.parse(text) returns text
as 'pg_net'
language C strict;


grant all on schema net to postgres;
grant all on all tables in schema net to postgres;
