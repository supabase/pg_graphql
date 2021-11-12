select jsonb_pretty(
    (gql.parse($$

        query {
          account(id: 1) {
            name
          }
        }

    $$)).ast::jsonb
)
