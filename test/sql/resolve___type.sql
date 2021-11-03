select jsonb_pretty(
    gql.dispatch($$
    {
      __type(name: "Account") {
        kind
        fields {
            name
        }
      }
    }
    $$)
);
