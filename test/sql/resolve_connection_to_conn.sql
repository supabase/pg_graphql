select jsonb_pretty(
    gql.resolve($$
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
