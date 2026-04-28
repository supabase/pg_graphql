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

    -- 6) Per-schema filtering across two schemas.
    -- Set up a second schema with its own table and add it to search_path.
    create schema priv;
    create table priv.secret(
        id serial primary key,
        token text not null
    );
    insert into priv.secret(token) values ('s1');
    grant usage on schema priv to public;
    grant select on priv.secret to public;
    set local search_path = public, priv;

    -- 6a) public=on, priv=on: both schemas' types and Query fields are visible.
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';
    comment on schema priv   is e'@graphql({"inflect_names": true, "introspection": true})';
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Account") { name kind }
            }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Secret") { name kind }
            }
        $$)
    );
    select jsonb_path_query_array(
        graphql.resolve($$
            { __schema { queryType { fields { name } } } }
        $$)::jsonb,
        '$.data.__schema.queryType.fields[*].name ? (@ like_regex "^(account|secret)Collection$")'
    );

    -- 6b) public=on, priv=off: priv's types/fields hidden, public still visible.
    -- Runtime queries against priv.secret still resolve.
    comment on schema priv is e'@graphql({"inflect_names": true, "introspection": false})';
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Account") { name kind }
            }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Secret") { name kind }
            }
        $$)
    );
    select jsonb_path_query_array(
        graphql.resolve($$
            { __schema { queryType { fields { name } } } }
        $$)::jsonb,
        '$.data.__schema.queryType.fields[*].name ? (@ like_regex "^(account|secret)Collection$")'
    );
    -- Runtime data query against the disabled schema still works.
    select jsonb_pretty(
        graphql.resolve($$
            { secretCollection { edges { node { id token } } } }
        $$)
    );

    -- 6c) public=off, priv=on: only priv's types/fields visible.
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": false})';
    comment on schema priv   is e'@graphql({"inflect_names": true, "introspection": true})';
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Account") { name kind }
            }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Secret") { name kind }
            }
        $$)
    );
    select jsonb_path_query_array(
        graphql.resolve($$
            { __schema { queryType { fields { name } } } }
        $$)::jsonb,
        '$.data.__schema.queryType.fields[*].name ? (@ like_regex "^(account|secret)Collection$")'
    );

    -- 6d) public=off, priv=off: top-level __schema/__type blocked entirely.
    -- Runtime queries against either schema still resolve.
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": false})';
    comment on schema priv   is e'@graphql({"inflect_names": true, "introspection": false})';
    select jsonb_pretty(
        graphql.resolve($$
            {
              __schema { queryType { name } }
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
    select jsonb_pretty(
        graphql.resolve($$
            { accountCollection { edges { node { id } } } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { secretCollection { edges { node { id } } } }
        $$)
    );
rollback;
