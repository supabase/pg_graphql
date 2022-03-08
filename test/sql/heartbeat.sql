begin;

    -- check that the resolver works
    select graphql.resolve($${ utcNow: heartbeat }$$) -> 'data' ->> 'utcNow' like '2%';

    -- 'heartbeat' should be visible in an empty project
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Query") {
            fields {
                name
            }
          }
        }
        $$)
    );

    create table account(
        id serial primary key,
        name varchar(255)
    );

    -- now that the project is not empty, 'heartbeat' should not be visible
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Query") {
            fields {
                name
            }
          }
        }
        $$)
    );

rollback;
