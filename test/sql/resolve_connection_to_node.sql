select jsonb_pretty(
    gql.resolve($$
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
