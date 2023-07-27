begin;

    create function add_ints(a int, b int)
        returns int language sql
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addInts(a: 40, b: 2)
        }
    $$));

rollback;