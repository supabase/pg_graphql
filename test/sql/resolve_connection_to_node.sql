select jsonb_pretty(
    gql.dispatch($$
    {
      allBlogs {
        edges {
          node {
            ownerId
            owner {
              id
            }
          }
        }
      }
    }
    $$)
);
