begin;

    create table "Account"(
      id serial primary key,
      name text not null
    );

    create table "EmailAddress"(
      id serial primary key,
      "accountId" int not null, -- note: no foreign key
      "isPrimary" bool not null,
      address text not null
    );

    comment on table "EmailAddress" is e'
        @graphql({
            "foreign_keys": [
              {
                "local_name": "addresses",
                "local_columns": ["accountId"],
                "foreign_name": "account",
                "foreign_schema": "public",
                "foreign_table": "Account",
                "foreign_columns": ["id"]
              }
            ]
        })';

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
