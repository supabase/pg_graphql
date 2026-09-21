begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';

    create table "Account"(
      id serial primary key,
      name text not null
    );

    create table "EmailAddress"(
      id serial primary key,
      "accountId" int not null references "Account"(id),
      "isPrimary" bool not null,
      address text not null
    );

    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "EmailAddress") {
            kind
            fields {
                name type { kind name ofType { name }  }
            }
          }
        }
        $$)
    );

rollback;
