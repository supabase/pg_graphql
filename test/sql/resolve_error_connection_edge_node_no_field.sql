begin;

    create table account(
        id int primary key
    );


    select graphql.resolve($$
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
