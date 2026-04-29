begin;
    -- Mirrors the "Introspection" section of docs/configuration.md.
    -- The fixture sets `inflect_names: true` on `public` with no `introspection`.
    -- Reset to a clean default-disabled state.
    comment on schema public is null;

    create table public.blog(id serial primary key, content text not null);
    insert into public.blog(content) values ('hello');

    -- 1) Default state: __schema and __type are both blocked.
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { queryType { name } } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Query") { name } }
        $$)
    );

    -- 2) Normal data queries are unaffected by introspection being off.
    select jsonb_pretty(
        graphql.resolve($$
            { blogCollection { edges { node { id content } } } }
        $$)
    );

    -- 3) Enabling introspection for a schema (docs first example).
    -- Without inflect_names, the type is reachable by its un-inflected name.
    comment on schema public is e'@graphql({"introspection": true})';
    select jsonb_pretty(
        graphql.resolve($$
            { __schema { queryType { name } } }
        $$)
    );
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "blog") { kind name } }
        $$)
    );

    -- 4) Composition: the directive merges with inflect_names; the type
    -- is now reachable as "Blog".
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';
    select jsonb_pretty(
        graphql.resolve($$
            { __type(name: "Blog") { kind name } }
        $$)
    );

    -- 5) Explicitly disabling it (docs second example).
    comment on schema public is e'@graphql({"introspection": false})';
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

    -- 6) "Enabling introspection on selective schemas" — full setup from the docs.
    create schema private;

    comment on schema public  is e'@graphql({"inflect_names": true, "introspection": true})';
    comment on schema private is e'@graphql({"inflect_names": true, "introspection": false})';

    create table private.account(id serial primary key, email text not null);

    grant usage on schema private to public;
    grant select, insert on private.account to public;
    grant usage, select on sequence private.account_id_seq to public;

    insert into private.account(email) values ('alice@example.com');

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

    -- Non-existent types also return null, so an attacker cannot tell
    -- whether "Account" is a hidden type in a disabled schema or simply
    -- doesn't exist at all. The two responses must be indistinguishable.
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

    -- Built-in scalars and meta-types continue to appear in __schema.types
    -- regardless of which exposed schemas have introspection disabled.
    select jsonb_path_query_array(
        graphql.resolve($$
            { __schema { types { kind name } } }
        $$)::jsonb,
        '$.data.__schema.types[*] ? (@.name like_regex "^(Int|Float|String|Boolean|ID|Cursor|BigInt|BigFloat|Date|Datetime|Time|UUID|JSON|__Schema|__Type|__Field|__InputValue|__EnumValue|__Directive|__TypeKind|__DirectiveLocation)$")'
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

    -- ============================================================
    -- Field-by-field coverage of every introspection type:
    --   __Schema, __Type, __Field, __InputValue, __EnumValue,
    --   __Directive, __TypeKind, __DirectiveLocation.
    -- Setup at this point: public=on, private=off, Blog table.
    -- ============================================================

    -- __Schema: description, queryType, mutationType, subscriptionType.
    -- (`types` is exercised above.)
    select jsonb_pretty(
        graphql.resolve($$
            {
              __schema {
                description
                queryType { name }
                mutationType { name }
                subscriptionType { name }
              }
            }
        $$)
    );

    -- __Schema.directives covers every __Directive field
    -- (name, description, isRepeatable, locations, args) and every
    -- __InputValue field on the directive arguments.
    select jsonb_pretty(
        graphql.resolve($$
            {
              __schema {
                directives {
                  name
                  description
                  isRepeatable
                  locations
                  args {
                    name
                    description
                    defaultValue
                    isDeprecated
                    deprecationReason
                    type { kind name ofType { kind name } }
                  }
                }
              }
            }
        $$)
    );

    -- __Type basic and collection-typed fields on an OBJECT type.
    -- Covers description, interfaces, possibleTypes, enumValues,
    -- inputFields. (`specifiedByURL` is declared on __Type in the
    -- schema but the resolver does not currently handle it.)
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Blog") {
                kind
                name
                description
                interfaces { name }
                possibleTypes { name }
                enumValues { name }
                inputFields { name }
              }
            }
        $$)
    );

    -- __Type.fields covers every __Field field, including the
    -- nested __Type returned by `type` and the __InputValue list
    -- returned by `args`. Filter to id/content for stable output.
    select jsonb_path_query_array(
        graphql.resolve($$
            {
              __type(name: "Blog") {
                fields {
                  name
                  description
                  isDeprecated
                  deprecationReason
                  type { kind name ofType { kind name } }
                  args {
                    name
                    description
                    defaultValue
                    isDeprecated
                    deprecationReason
                    type { kind name ofType { kind name } }
                  }
                }
              }
            }
        $$)::jsonb,
        '$.data.__type.fields[*] ? (@.name == "id" || @.name == "content")'
    );

    -- __Type.inputFields covers every __InputValue field against
    -- an INPUT_OBJECT type (BlogInsertInput).
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "BlogInsertInput") {
                kind
                name
                inputFields {
                  name
                  description
                  defaultValue
                  isDeprecated
                  deprecationReason
                  type { kind name ofType { kind name } }
                }
              }
            }
        $$)
    );

    -- __Type.enumValues covers every __EnumValue field against
    -- a built-in ENUM type (OrderByDirection).
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "OrderByDirection") {
                kind
                name
                description
                enumValues {
                  name
                  description
                  isDeprecated
                  deprecationReason
                }
              }
            }
        $$)
    );

    -- __Type.ofType is exercised by walking the wrapping types
    -- around the `blogCollection` field on Query.
    select jsonb_path_query_first(
        graphql.resolve($$
            {
              __schema {
                queryType {
                  fields {
                    name
                    type { kind name ofType { kind name ofType { kind name } } }
                  }
                }
              }
            }
        $$)::jsonb,
        '$.data.__schema.queryType.fields[*] ? (@.name == "blogCollection")'
    );

    -- All values of the __TypeKind enum.
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "__TypeKind") {
                kind
                name
                description
                enumValues { name description isDeprecated deprecationReason }
              }
            }
        $$)
    );

    -- All values of the __DirectiveLocation enum.
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "__DirectiveLocation") {
                kind
                name
                enumValues { name description }
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
