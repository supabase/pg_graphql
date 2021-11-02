select gql.dispatch($$
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
$$);
