begin;

    create table account(
        id int primary key
    );


    select gql.resolve($$
    {
      account(id: "WyJhY2NvdW50IiwgMV0=") {
        id
        shouldFail
      }
    }
    $$);

rollback;
