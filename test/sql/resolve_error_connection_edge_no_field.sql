begin;

    create table account(
        id int primary key
    );


    select graphql.resolve($$
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
