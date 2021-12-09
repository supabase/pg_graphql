begin;

    create table account(
        id int primary key
    );


    select graphql.resolve($$
    {
      allAccounts {
        dneField
        totalCount
      }
    }
    $$);

rollback;
