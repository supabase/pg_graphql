begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';
    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    comment on table public.account is E'@graphql({"name": "UserAccount"})';

    select jsonb_pretty(
        jsonb_path_query(
            graphql.resolve($$
                query IntrospectionQuery {
                  __schema {
                    types {
                      name
                    }
                  }
                }
            $$),
            '$.data.__schema.types[*].name ? (@ starts with "UserAccount")'
        )
    );

rollback;
