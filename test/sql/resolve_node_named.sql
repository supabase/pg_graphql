begin;

    create table account(
        id int primary key
    );


    insert into public.account(id)
    select * from generate_series(1,5);


    select graphql.resolve(
        $$
        query GetAccount($nodeId: ID!) {
          account(nodeId: $nodeId) {
            id
          }
        }
        $$,
        '{"nodeId": "WyJhY2NvdW50IiwgMV0="}'::jsonb
    );

rollback;
