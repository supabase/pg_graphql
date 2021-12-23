begin;
    create table account(
        id int primary key
    );

    insert into public.account(id)
    values
        (1),
        (2),
        (3);


    -- Filter by Int
    select jsonb_pretty(
        graphql.resolve($$
            {
              allAccounts(filter: {id: 2}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

rollback;
