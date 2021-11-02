select jsonb_pretty(
    gql.dispatch($$
        {
          allAccounts {
            totalCount
            pageInfo{
                startCursor
                endCursor
                hasPreviousPage
                hasNextPage
            }
            edges {
              cursor
              node {
                id
                nodeId
                email
              }
            }
          }
        }
    $$)
);
