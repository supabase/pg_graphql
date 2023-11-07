begin;

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
