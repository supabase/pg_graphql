select jsonb_pretty(
    (graphql.parse($$

        query {
          account(id: 1) {
            name
          }
        }

    $$)).ast::jsonb
)
