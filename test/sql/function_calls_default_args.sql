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
        b int default null,
        c bigint default null,
        d real default null,
        e double precision default null,
        f numeric default null,
        g bool default null,
        h uuid default null,
        i text default null,
        j date default null,
        k time default null,
        l time with time zone default null,
        m timestamp default null,
        n timestamptz default null,
        o json default null,
        p jsonb default null,
        q char(2) default null,
        r varchar(2) default null
    )
        returns text language plpgsql immutable
    as $$
    begin

        if
            a is null and
            b is null and
            c is null and
            d is null and
            e is null and
            f is null and
            g is null and
            h is null and
            i is null and
            j is null and
            k is null and
            l is null and
            m is null and
            n is null and
            o is null and
            p is null and
            q is null and
            r is null
        then
            return 'all args null';
        end if;

        return
            a::text || ', ' ||
            b::text || ', ' ||
            c::text || ', ' ||
            d::text || ', ' ||
            e::text || ', ' ||
            f::text || ', ' ||
            g::text || ', ' ||
            h::text || ', ' ||
            i::text || ', ' ||
            j::text || ', ' ||
            k::text || ', ' ||
            l::text || ', ' ||
            m::text || ', ' ||
            n::text || ', ' ||
            o::text || ', ' ||
            p::text || ', ' ||
            q::text || ', ' ||
            r::text;
    end;
    $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            funcWithNullDefaults
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
        query {
            funcWithNullDefaults(
                a: 1,
                b: 2,
                c: 3,
                d: 1.1,
                e: 2.3,
                f: "3.4",
                g: false,
                h: "8871277a-de9c-4156-b31f-5b4060001081",
                i: "text",
                j: "2023-07-28",
                k: "10:20",
                l: "10:20+05:30",
                m: "2023-07-28 12:39:05",
                n: "2023-07-28 12:39:05+05:30",
                o: "{\"a\": {\"b\": \"foo\"}}",
                p: "{\"a\": {\"b\": \"foo\"}}",
                q: "hi",
                r: "ho"
            )
        }
    $$));

    create function defaul_null_mixed_case(
        a smallint default null,
        b integer default NULL,
        c integer default NuLl
    )
        returns text language plpgsql immutable
    as $$
    begin
        return 'mixed case';
    end;
    $$;

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
