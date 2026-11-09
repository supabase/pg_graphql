begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';

    create table account(
        id serial primary key,
        balance numeric not null,
        score int not null
    );

    -- Aggregates are opt-in per table.
    comment on table account is e'@graphql({"aggregate": {"enabled": true}})';

    insert into public.account(balance, score)
    values
        (100.00, 5),
        (250.00, 9);

    -- Superuser sees every aggregatable column, including `balance`.
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "AccountSumAggregateResult") {
                kind
                fields { name }
              }
            }
        $$)
    );

    create role api;

    -- Grant access to GQL
    grant usage on schema graphql to api;

    -- `api` may read id + score, but NOT balance.
    grant usage on schema public to api;
    grant all on all tables in schema public to api;
    revoke select on public.account from api;
    grant select (id, score) on public.account to api;

    set role api;

    -- The aggregate result types must not expose the non-selectable `balance`
    -- column (schema/introspection leak). Only `score` should appear.
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "AccountSumAggregateResult") {
                kind
                fields { name }
              }
            }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "AccountMaxAggregateResult") {
                kind
                fields { name }
              }
            }
        $$)
    );

    -- Aggregating a permitted column still works.
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection {
                aggregate {
                  sum { score }
                }
              }
            }
        $$)
    );

    reset role;
rollback;
