select gql.resolve($$
{
  allAccounts {
    totalCount
    edges {
        dneField
    }
  }
}
$$);
