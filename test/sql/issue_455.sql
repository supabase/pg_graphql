begin;

    create schema a1;
    grant usage on schema a1 to public;
    create table a1.foo(
        id int primary key
    );
    grant select on table a1.foo to public;
    insert into a1.foo values (1);

    create function a1.the_foo()
        returns a1.foo
        stable
        language sql
    as $$
        select f from a1.foo f where f.id = 1;
    $$;
    grant execute on function a1.the_foo() to public;

    create schema a2;
    grant usage on schema a2 to public;

    create function a2.get_the_foo()
        returns a1.foo
        stable
        language sql
    as $$
        select * from a1.the_foo();
    $$;
    grant execute on function a2.get_the_foo() to public;

    set local search_path to a2;

    select graphql.resolve($$
        query {
            get_the_foo {
                id
            }
        }
    $$) = '{"data": {"get_the_foo": {"id": 1}}}'::jsonb as function_returned_table;

    select graphql.resolve($$
        query {
            fooCollection {
                edges {
                    node {
                        id
                    }
                }
            }
        }
    $$) -> 'errors' -> 0 ->> 'message' = 'Unknown field "fooCollection" on type Query' as collection_not_exposed;

rollback;
