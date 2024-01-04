begin;

    create view account as
    select
      1 as foo,
      2 as bar;

    create function returns_account()
        returns account language sql stable
    as $$ select foo, bar from account; $$;

    -- Account should not be visible because the view has no primary key
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            __typename
          }
        }
        $$)
    );

    -- returnsAccount should also not be visible because account has no primary key
    select jsonb_pretty(
        graphql.resolve($$
            query IntrospectionQuery {
              __schema {
                queryType {
                  fields {
                    name
                  }
                }
              }
            }
        $$)
    );

    comment on view account is e'
    @graphql({
        "primary_key_columns": ["foo"]
    })';

    -- Account should be visible because the view is selectable and has a primary key
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            __typename
          }
        }
        $$)
    );

    -- returnsAccount should also be visible because account has a primary key and is selectable
    select jsonb_pretty(
        graphql.resolve($$
            query IntrospectionQuery {
              __schema {
                queryType {
                  fields {
                    name
                  }
                }
              }
            }
        $$)
    );



rollback;
