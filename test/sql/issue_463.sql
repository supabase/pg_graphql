begin;

    create table foo(
        id int primary key
    );

    insert into foo (id) values (1);

    create or replace function bar(foo)
        returns int[]
        language sql
        stable
    as $$
        select array[1, 2, 3]::int[];
    $$;

    select graphql.resolve($$
        query {
            fooCollection {
                edges {
                    node {
                        id
                        bar
                    }
                }
            }
        }
        $$
    );

    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Foo") {
            kind
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
