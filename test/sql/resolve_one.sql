begin;
    create table account(
        id int primary key,
        is_verified bool,
        name text
    );

    insert into public.account(id, is_verified, name)
    values
        (1, true, 'foo'),
        (2, true, 'bar'),
        (3, false, 'baz');

    create table blog(
        id serial primary key,
        owner_id integer not null references account(id),
        name varchar(255) not null
    );

    insert into blog(owner_id, name)
    values
        (1, 'Blog 1'),
        (2, 'Blog 2'),
        (2, 'Blog 3'),
        (3, 'Blog 4');

    savepoint a;

    -- Valid nodeId that is present
    select graphql.encode('["public", "account", 2]'::jsonb);
    select jsonb_pretty(
        graphql.resolve($$
            {
              account(nodeId: "WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd") {
                id
                nodeId
                blogCollection {
                  edges {
                    node {
                      id
                      name
                    }
                  }
                }
              }
            }
        $$)
    );


    -- Valid nodeId that is not present
    select graphql.encode('["public", "account", 99]'::jsonb);
    select jsonb_pretty(
        graphql.resolve($$
            {
              account(nodeId: "WyJwdWJsaWMiLCAiYWNjb3VudCIsIDk5XQ==") {
                id
                nodeId
              }
            }
        $$)
    );

    -- Valid nodeId variable
    select graphql.resolve($$
    query GetOne($nid: ID!) {
      account(
        nodeId: $nid
      ) {
        id
        nodeId
      }
    }
    $$, '{"nid": "WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd"}');


    select jsonb_pretty(
        graphql.resolve($$
            {
              account(nodeId: "") {
                id
                nodeId
              }
            }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
            {
              account(nodeId: null) {
                id
                nodeId
              }
            }
        $$)
    );

    -- Valid nodeId for incorrect table
    select graphql.encode('["public", "blog", 1]'::jsonb);
    select jsonb_pretty(
        graphql.resolve($$
            {
              account(nodeId: "WyJwdWJsaWMiLCAiYmxvZyIsIDFd") {
                id
                nodeId
              }
            }
        $$)
    );

    -- Confirm table matching continues to work when names are quoted
    create table "Foo"(
        id serial primary key,
        name varchar(255) not null
    );
    insert into "Foo"(name) values ('abc');

    select graphql.encode('["public", "Foo", 1]'::jsonb);
    select jsonb_pretty(
        graphql.resolve($$
            {
              foo(nodeId: "WyJwdWJsaWMiLCAiRm9vIiwgMV0=") {
                id
                nodeId
              }
            }
        $$)
    );



rollback;
