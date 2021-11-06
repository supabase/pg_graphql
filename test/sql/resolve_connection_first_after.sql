select jsonb_pretty(
    gql.dispatch($$
        {
          allAccounts(first: 2, after: "WyJhY2NvdW50IiwgM10=") {
            edges {
              node {
                nodeId
                id
              }
            }
          }
        }
    $$)
);
