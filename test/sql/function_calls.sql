begin;

    -- Only volatilve functions appear on the mutation object

    create function add_smallints(a smallint, b smallint)
        returns smallint language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addSmallints(a: 1, b: 2)
        }
    $$));

    create function add_ints(a int, b int)
        returns int language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addInts(a: 2, b: 3)
        }
    $$));

    create function add_bigints(a bigint, b bigint)
        returns bigint language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addBigints(a: 3, b: 4)
        }
    $$));

    create function add_reals(a real, b real)
        returns real language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addReals(a: 4.5, b: 5.6)
        }
    $$));

    create function add_doubles(a double precision, b double precision)
        returns double precision language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addDoubles(a: 7.8, b: 9.1)
        }
    $$));

    create function and_bools(a bool, b bool)
        returns bool language sql volatile
    as $$ select a and b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            andBools(a: true, b: false)
        }
    $$));

rollback;