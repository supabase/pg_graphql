select jsonb_pretty(
    (graphql.parse_query($$

        query {
          account(id: 1) {
            name
          }
        }

    $$))
)
