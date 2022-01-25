begin;
    create table account(
        id int primary key
    );


    insert into public.account(id)
    select * from generate_series(1,5);


    select graphql.resolve(
        $$
        query FirstNAccounts($first: Int!) {
          accountCollection(first: $first) {
            edges {
              node {
                id
              }
            }
          }
        }
        $$,
        '{"first": 2}'::jsonb
    );

rollback;
