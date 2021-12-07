begin;

    create table account(
        id int primary key
    );


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

rollback;
