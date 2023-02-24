begin;
    create table book(
        id int primary key,
        is_verified bool
    );

    insert into public.book(id, is_verified)
    values
        (1, true);

    savepoint a;

    -- Should be skipped
    select jsonb_pretty(
        graphql.resolve($$
            {
              bookCollection {
                edges {
                  node {
                    id
                    isVerified @skip( if: true )
                  }
                }
              }
            }
        $$)
    );

    -- Should not be skipped
    select jsonb_pretty(
        graphql.resolve($$
            {
              bookCollection {
                edges {
                  node {
                    id
                    isVerified @skip( if: false )
                  }
                }
              }
            }
        $$)
    );

    rollback to savepoint a;

rollback;
