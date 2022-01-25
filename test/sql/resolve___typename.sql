begin;

    create table account(
        id int primary key
    );


    insert into public.account(id)
    values
        (1);


    select jsonb_pretty(
        graphql.resolve($$
    {
      accountCollection {
        __typename
        pageInfo {
          __typename
        }
        edges {
          __typename
          node {
            __typename
          }
        }
      }
    }
        $$)
    );


    select graphql.resolve($$
    {
      account(id: "WyJhY2NvdW50IiwgMV0=") {
        __typename
      }
    }
    $$);

rollback;
