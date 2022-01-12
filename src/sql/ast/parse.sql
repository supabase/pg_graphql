create type graphql.parse_result AS (
    ast text,
    error text
);

create function graphql.parse(text)
    returns graphql.parse_result
    language c
    immutable
as 'pg_graphql', 'parse';
