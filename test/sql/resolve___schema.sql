select gql.dispatch($$
    query IntrospectionQuery {
      __schema {
        queryType {
          name
        }
        mutationType {
          name
        }
        types {
          kind
          name
        }
        directives {
          name
          description
          locations
        }
      }
    }
$$);
