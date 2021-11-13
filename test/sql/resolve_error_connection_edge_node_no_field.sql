select gql.resolve($$
{
  allAccounts {
    edges {
      cursor
      node {
        dneField
      }
    }
  }
}
$$);
