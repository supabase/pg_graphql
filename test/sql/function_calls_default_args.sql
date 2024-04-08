begin;

    create function func_with_null_defaults(
        a smallint default null,
        b integer default null,
        c boolean default null,
        d real default null,
        e double precision default null,
        f text default null,
        g uuid default null
    )
        returns text language sql immutable
    as $$ select a::text || b::text || c::text || d::text || e::text || f::text || g::text; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            funcWithNullDefaults
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
        query {
            funcWithNullDefaults(a: 1, b: 2, c: false, d: 1.1, e: 2.3, f: "f_arg", g: "8871277a-de9c-4156-b31f-5b4060001081")
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
        query {
            funcWithNullDefaults(a: 1, c: false, e: 2.3, g: "8871277a-de9c-4156-b31f-5b4060001081")
        }
    $$));

    select jsonb_pretty(
        graphql.resolve($$
            query IntrospectionQuery {
              __schema {
                queryType {
                  name
                  fields {
                    name
                    args {
                      name
                      defaultValue
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
            }
        $$)
    );

rollback;
