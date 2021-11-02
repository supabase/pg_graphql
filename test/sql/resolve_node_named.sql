select gql.dispatch(
    $$
    query GetAccount($nodeId: ID!) {
      account(nodeId: $nodeId) {
        id
      }
    }
    $$,
    '{"nodeId": "WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd"}'::jsonb
);
