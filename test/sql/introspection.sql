begin;
    savepoint a;

    -- Introspection enabled on one schema and disabled on another

    create schema private;

    comment on schema public  is e'@graphql({"inflect_names": true, "introspection": true})';
    comment on schema private is e'@graphql({"inflect_names": true, "introspection": false})';

    create table public.blog(id serial primary key, content text not null);
    create table private.account(id serial primary key, email text not null);

    insert into public.blog(id, content) values (1, 'hello, world');
    insert into private.account(id, email) values (1, 'alice@example.com');

    set local search_path = public, private;

    -- The `__type` field successfully resolves types belonging to the `public` schema:
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );

    -- But it returns `null` for types in the `private` schema:
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Account") { kind name } }
        $$)
    );

    -- Any non-existent types in the `private` schema also return null, to make it impossible for an attacker to enumerate types by guessing:
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "User") { kind name } }
        $$)
    );

    -- Built in types and Blog types, not Account types
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { types { kind name } } }
        $$)
    );

    -- queryType and mutationType list Blog types, not Account types
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { mutationType { fields { name } } } }
        $$)
    );

    -- non-introspection queries continue to work
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

    -- Introspection disabled on both schemas

    comment on schema public  is e'@graphql({"inflect_names": true, "introspection": false})';
    comment on schema private is e'@graphql({"inflect_names": true, "introspection": false})';

    -- The `__type` field returns error for types belonging to the `public` schema:
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );

    -- and for the `private` schema:
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Account") { kind name } }
        $$)
    );

    -- same for any non-existent types
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "User") { kind name } }
        $$)
    );

    -- The `__schema` field also returns an error
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { types { kind name } } }
        $$)
    );

    -- same for queryType and mutationType
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { mutationType { fields { name } } } }
        $$)
    );

    -- non-introspection queries continue to work
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

    rollback to savepoint a;

    -- By default introspection is disabled

    create schema private;

    create table public.blog(id serial primary key, content text not null);
    create table private.account(id serial primary key, email text not null);

    insert into public.blog(id, content) values (1, 'hello, world');
    insert into private.account(id, email) values (1, 'alice@example.com');

    set local search_path = public, private;

    -- both `__type` and `__schema` queries error out
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { types { kind name } } }
        $$)
    );

    rollback to savepoint a;

    -- off/on: public=OFF, private=ON
    -- introspection_enabled() uses any(), so introspection is available when
    -- private opts in. public types must still be hidden.

    create schema private;

    comment on schema public  is e'@graphql({"inflect_names": true, "introspection": false})';
    comment on schema private is e'@graphql({"inflect_names": true, "introspection": true})';

    create table public.blog(id serial primary key, content text not null);
    create table private.account(id serial primary key, email text not null);

    insert into public.blog(id, content) values (1, 'hello, world');
    insert into private.account(id, email) values (1, 'alice@example.com');

    set local search_path = public, private;

    -- public schema type returns null (public=OFF)
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );

    -- private schema type returns data (private=ON)
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Account") { kind name } }
        $$)
    );

    -- __schema lists private types but not public types
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { mutationType { fields { name } } } }
        $$)
    );

    rollback to savepoint a;

    -- named fragment spread containing introspection fields
    -- fragment expansion happens before the field_map lookup so the same
    -- "Unknown field" error must fire as for an inline introspection query

    create table public.blog(id serial primary key, content text not null);
    set local search_path = public;

    select jsonb_pretty(
        graphql.resolve($$
            fragment IntrospectSchema on Query { __schema { types { kind name } } }
            { ...IntrospectSchema }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
            fragment IntrospectType on Query { __type(name: "blog") { kind name } }
            { ...IntrospectType }
        $$)
    );

    rollback to savepoint a;

    -- mixed query: introspection field + data field with introspection disabled
    -- when any field errors the entire data object becomes null, so
    -- blogCollection result is lost even though it executed successfully

    create table public.blog(id serial primary key, content text not null);
    insert into public.blog(id, content) values (1, 'hello, world');
    set local search_path = public;

    select jsonb_pretty(
        graphql.resolve($$
            {
                __schema { types { name } }
                blogCollection { edges { node { id content } } }
            }
        $$)
    );

rollback;
