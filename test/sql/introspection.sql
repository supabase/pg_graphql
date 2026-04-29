begin;
    -- Mirrors the "Introspection" section of docs/configuration.md.
    -- The fixture sets `inflect_names: true` on `public` with no `introspection`.
    -- Reset to match the docs setup exactly.
    comment on schema public is null;

    -- Enabling introspection for a schema (docs first example).
    comment on schema public is e'@graphql({"introspection": true})';
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { queryType { name } } }
        $$)
    );

    -- Explicitly disabling it (docs second example).
    comment on schema public is e'@graphql({"introspection": false})';
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { queryType { name } } }
        $$)
    );

    -- "Enabling introspection on selective schemas" — full setup from the docs.
    create schema private;

    comment on schema public  is e'@graphql({"inflect_names": true, "introspection": true})';
    comment on schema private is e'@graphql({"inflect_names": true, "introspection": false})';

    create table public.blog(id serial primary key, content text not null);
    create table private.account(id serial primary key, email text not null);

    grant usage on schema private to public;
    grant select, insert on private.account to public;
    grant usage, select on sequence private.account_id_seq to public;

    insert into public.blog(content)    values ('hello');
    insert into private.account(email)  values ('alice@example.com');

    set local search_path = public, private;

    -- __schema and __type are available because at least one exposed schema
    -- (public) has introspection enabled.
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );

    -- Types in the disabled `private` schema return null.
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Account") { kind name } }
        $$)
    );

    -- Non-existent types also return null, so an attacker cannot enumerate
    -- types by guessing.
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "User") { kind name } }
        $$)
    );

    -- __schema.types lists Blog and its derived types but not Account's.
    select jsonb_path_query_array(
        graphql.resolve($$
            { __schema { types { kind name } } }
        $$)::jsonb,
        '$.data.__schema.types[*] ? (@.name like_regex "^(Blog|Account)")'
    );

    -- queryType.fields is filtered the same way: blogCollection appears,
    -- accountCollection is hidden.
    select jsonb_path_query_array(
        graphql.resolve($$
            { __schema { queryType { fields { name } } } }
        $$)::jsonb,
        '$.data.__schema.queryType.fields[*].name ? (@ like_regex "^(blog|account)Collection$")'
    );

    -- Non-introspection queries are not affected by the directive:
    -- accountCollection still resolves normally.
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection {
                edges {
                  node {
                    id
                    email
                  }
                }
              }
            }
        $$)
    );

    -- Truth table from the docs: four combinations across the two schemas.

    -- Row 1: public=on, private=on → __schema/__type available, both types visible.
    comment on schema public  is e'@graphql({"inflect_names": true, "introspection": true})';
    comment on schema private is e'@graphql({"inflect_names": true, "introspection": true})';
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Account") { kind name } }
        $$)
    );
    select jsonb_path_query_array(
        graphql.resolve($$
            { __schema { queryType { fields { name } } } }
        $$)::jsonb,
        '$.data.__schema.queryType.fields[*].name ? (@ like_regex "^(blog|account)Collection$")'
    );

    -- Row 2: public=on, private=off → Blog visible, Account hidden.
    comment on schema public  is e'@graphql({"inflect_names": true, "introspection": true})';
    comment on schema private is e'@graphql({"inflect_names": true, "introspection": false})';
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Account") { kind name } }
        $$)
    );
    select jsonb_path_query_array(
        graphql.resolve($$
            { __schema { queryType { fields { name } } } }
        $$)::jsonb,
        '$.data.__schema.queryType.fields[*].name ? (@ like_regex "^(blog|account)Collection$")'
    );

    -- Row 3: public=off, private=on → Account visible, Blog hidden.
    comment on schema public  is e'@graphql({"inflect_names": true, "introspection": false})';
    comment on schema private is e'@graphql({"inflect_names": true, "introspection": true})';
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Account") { kind name } }
        $$)
    );
    select jsonb_path_query_array(
        graphql.resolve($$
            { __schema { queryType { fields { name } } } }
        $$)::jsonb,
        '$.data.__schema.queryType.fields[*].name ? (@ like_regex "^(blog|account)Collection$")'
    );

    -- Row 4: public=off, private=off → __schema/__type blocked entirely with
    -- "Unknown field" errors. Non-introspection queries continue unchanged.
    comment on schema public  is e'@graphql({"inflect_names": true, "introspection": false})';
    comment on schema private is e'@graphql({"inflect_names": true, "introspection": false})';
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { queryType { name } } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { blogCollection { edges { node { id content } } } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { accountCollection { edges { node { id email } } } }
        $$)
    );
rollback;
