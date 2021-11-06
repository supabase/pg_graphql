select jsonb_pretty(
    gql.dispatch($$
        {
          allAccounts(last: 2, before: "WyJhY2NvdW50IiwgM10=") {
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
