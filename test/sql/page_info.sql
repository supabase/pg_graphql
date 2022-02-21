begin;
    create table account(
        id int primary key,
        is_verified bool
    );


    -- hasNextPage and hasPreviousPage should be non-null on empty collection
    -- startCursor and endCursor may be null
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
          }
        }
        $$)
    );
