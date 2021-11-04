select jsonb_pretty(
    gql.dispatch($$
{
  allAccounts {
    edges {
      node {
        id
        email
        blogs {
          totalCount
            edges {
              node {
                name
            }
          }
        }
      }
    }
  }
}
    $$)
);
