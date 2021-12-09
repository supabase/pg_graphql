begin;

    create table account(
        id int primary key
    );


    select graphql.resolve($$
    {
      account(id: "WyJhY2NvdW50IiwgMV0=") {
        id
        shouldFail
      }
    }
    $$);

rollback;
