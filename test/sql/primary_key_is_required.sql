begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';

    savepoint a;

    create table account(
        id serial primary key
    );

    -- Should be visible because it has a primary ky
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            name
          }
        }
        $$)
    );

    rollback to savepoint a;

    create table account(
        id serial
    );

    -- Should NOT be visible because it does not have a primary ky
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            name
          }
        }
        $$)
    );

rollback;
