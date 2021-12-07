begin;

    create table account(
        id int primary key
    );


    select gql.resolve($$
    {
      allAccounts {
        edges {
          cursor
          node {
            dneField
          }
        }
      }
    }
    $$);

rollback;
