begin;
    -- The fixture sets `inflect_names: true` on `public` but no `introspection`.
    -- Reset the comment to start from a clean default-disabled state.
    comment on schema public is null;

    create table account(
        id serial primary key,
        email text not null
    );

    -- 1) Default state: __schema and __type both blocked
    select jsonb_pretty(
        graphql.resolve($$
            {
              __schema {
                queryType { name }
              }
            }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Query") { name }
            }
        $$)
    );

    -- 2) Normal data queries unaffected by introspection being off
    insert into account(email) values ('a@x.com');
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection {
                edges { node { id email } }
              }
            }
        $$)
    );

    -- 3) Opt in: introspection visible, type is reachable by its un-inflected name
    comment on schema public is e'@graphql({"introspection": true})';
    select jsonb_pretty(
        graphql.resolve($$
            {
              __schema {
                queryType { name }
              }
            }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "account") { name kind }
            }
        $$)
    );

    -- 4) Composition: directive merges with inflect_names; type name is now "Account"
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Account") { name kind }
            }
        $$)
    );

    -- 5) Explicit opt-out: blocked again
    comment on schema public is e'@graphql({"introspection": false})';
    select jsonb_pretty(
        graphql.resolve($$
            {
              __schema {
                queryType { name }
              }
            }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Account") { name }
            }
        $$)
    );
rollback;
