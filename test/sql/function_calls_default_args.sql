begin;

    create function both_args_optional(
        a smallint default null,
        b integer default null
    )
        returns text language plpgsql immutable
    as $$
    begin

        if a is null and b is null then
            return 'both null';
        end if;

        if a is null then
            return 'b = ' || b::text;
        end if;

        if b is null then
            return 'a = ' || a::text;
        end if;

        return 'a = ' || a::text || ', b = ' || b::text;
    end;
    $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            bothArgsOptional
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
        query {
            bothArgsOptional(a: 1)
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
        query {
            bothArgsOptional(b: 2)
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
        query {
            bothArgsOptional(a: 1, b: 2)
        }
    $$));

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
