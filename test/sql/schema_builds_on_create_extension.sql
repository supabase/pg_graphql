drop extension pg_graphql;
create extension pg_graphql;

select graphql.resolve($${ heartbeat }$$) -> 'data' ->> 'heartbeat' like '2%';
