select gql.dispatch($$
    {
      __type(name: "Account") {
        kind
        fields {
            name
        }
    }
}$$);
