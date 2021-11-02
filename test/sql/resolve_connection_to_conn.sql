select gql.dispatch($$
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
                title
            }
          }
        }
      }
    }
  }
}
$$);
