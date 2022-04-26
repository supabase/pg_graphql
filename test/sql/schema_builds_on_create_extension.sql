drop extension pg_graphql;
create extension pg_graphql;

select jsonb_pretty(
    graphql.resolve($$
    { heartbeat }
    $$)
);
