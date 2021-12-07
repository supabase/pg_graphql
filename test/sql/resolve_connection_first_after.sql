begin;
    create table account(
        id int primary key
    );


    insert into public.account(id)
    select * from generate_series(1,5);


    select jsonb_pretty(
        gql.resolve($$
            {
              allAccounts(first: 2, after: "WyJhY2NvdW50IiwgM10=") {
                edges {
                  node {
                    nodeId
                    id
                  }
                }
              }
            }
        $$)
    );

rollback;
