select gql.resolve(
    $$
    query GetAccount($nodeId: ID!) {
      account(nodeId: $nodeId) {
        id
      }
    }
    $$,
    '{"nodeId": "WyJhY2NvdW50IiwgMV0="}'::jsonb
);
