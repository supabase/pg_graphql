begin;
    -- Create a table with NOT NULL columns
    create table account(
        id serial primary key,
        name text not null
    );

    -- Create a view from the table
    create view person as
        select id, name from account;

    -- Add primary key directive so the view is exposed
    comment on view person is e'@graphql({"primary_key_columns": ["id"]})';

    -- Check that view columns are nullable by default (no NOT NULL constraint preserved)
    -- The "kind" should be a scalar type directly, not NON_NULL
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Person") {
            fields {
              name
              type {
                kind
                name
                ofType {
                  kind
                  name
                }
              }
            }
          }
        }
        $$)
    );

    -- Apply not_null directive to view columns
    comment on column person.id is e'@graphql({"not_null": true})';
    comment on column person.name is e'@graphql({"not_null": true})';

    -- Check that view columns are now non-nullable
    -- The "kind" should be NON_NULL with ofType containing the scalar type
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Person") {
            fields {
              name
              type {
                kind
                name
                ofType {
                  kind
                  name
                }
              }
            }
          }
        }
        $$)
    );

rollback;
