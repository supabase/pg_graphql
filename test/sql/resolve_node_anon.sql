begin;

    create table account(
        id int primary key
    );


    insert into public.account(id)
    select * from generate_series(1,5);


    select gql.resolve($$
    {
      account(id: "WyJhY2NvdW50IiwgMV0=") {
        id
        nodeId
      }
    }
    $$);

rollback;
