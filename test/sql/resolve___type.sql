select jsonb_pretty(
    gql.resolve($$
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
