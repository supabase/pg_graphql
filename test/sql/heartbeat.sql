select
    graphql.resolve($${ utcNow: heartbeat }$$) -> 'data' ->> 'utcNow' like '2%'
