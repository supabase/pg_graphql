begin;

    create table account(
        id int primary key
    );

    create table address(
        id int primary key,
        account_id int not null references account(id)
    );

    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            kind
            fields {
              name
              type {
                name
                kind
                ofType { name }
              }
            }
          }
        }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Address") {
            kind
            fields {
              name
              type {
                name
                kind
                ofType { name }
              }
            }
          }
        }
        $$)
    );

    alter table account enable row level security;

    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            kind
            fields {
              name
              type {
                name
                kind
                ofType { name }
              }
            }
          }
        }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Address") {
            kind
            fields {
              name
              type {
                name
                kind
                ofType { name }
              }
            }
          }
        }
        $$)
    );

    alter table account disable row level security;
    alter table address enable row level security;

    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            kind
            fields {
              name
              type {
                name
                kind
                ofType { name }
              }
            }
          }
        }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Address") {
            kind
            fields {
              name
              type {
                name
                kind
                ofType { name }
              }
            }
          }
        }
        $$)
    );

rollback;
