begin;

    create table account(
        id int primary key
    );


    select gql.resolve($$
    {
      allAccounts {
        dneField
        totalCount
      }
    }
    $$);

rollback;
