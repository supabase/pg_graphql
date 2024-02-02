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

    insert into account(id) select generate_series(1, 10);

    -- Forward pagination
    -- hasPreviousPage is false, hasNextPage is true
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(first: 5) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- hasPreviousPage is true, hasNextPage is true
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(first: 5, after: "WzJd" ) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- hasPreviousPage is true, hasNextPage is false
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(first: 5, after: "Wzdd" ) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- Backward pagination
    -- hasPreviousPage is true, hasNextPage is false
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(last: 5) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- hasPreviousPage is true, hasNextPage is true
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(last: 5, before: "Wzdd" ) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- hasPreviousPage is false, hasNextPage is true
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(last: 5, before: "WzJd" ) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- OFFSET ARG
    -- Only supported for forward pagination


    -- hasPreviousPage is false, hasNextPage is true
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(first: 2, offset: 0) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- hasPreviousPage is true, hasNextPage is true
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(first: 2, offset: 1) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- hasPreviousPage is true, hasNextPage is true
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(
            first: 1,
            offset: 1,
            after: "Wzdd" # id = 7
        ) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- hasPreviousPage is true, hasNextPage is false
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(
            first: 2,
            offset: 2,
            after: "Wzdd" # id = 7
        ) {
            pageInfo {
              hasNextPage
              hasPreviousPage
              startCursor
              endCursor
            }
            edges {
              cursor
              node {
                id
              }
            }
          }
        }
        $$)
    );


    -- Error States

    -- Offset doesn't work with "last"
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(
            last: 2,
            offset: 2,
        ) {
            edges {
              node {
                id
              }
            }
          }
        }
        $$)
    );

    -- Offset doesn't work with "before"
    select jsonb_pretty(
        graphql.resolve($$
        {
          accountCollection(
            last: 2,
            offset: 2,
        ) {
            edges {
              node {
                id
              }
            }
          }
        }
        $$)
    );

rollback;
