begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';

    create function "someFunc" (arg uuid)
        returns int
        immutable
        language sql
    as $$ select 1; $$;

    select jsonb_pretty(
        graphql.resolve($$
            {
            __type(name: "Query") {
                fields(includeDeprecated: true) {
                    name
                    args {
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
            }
        $$)
    );

rollback;
