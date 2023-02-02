begin;
    create table memo(
        id int primary key,
        contents text
    );

    insert into memo(id, contents)
    values
        (1, 'foo'),
        (2, 'bar'),
        (3, 'baz');

    savepoint a;

    -- Filter by Int
    select jsonb_pretty(
        graphql.resolve($$
            {
              memoCollection(filter: {contents: {startsWith: "b"}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );
    rollback to savepoint a;

rollback;
