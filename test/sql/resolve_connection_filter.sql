begin;
    create table account(
        id int primary key,
        is_verified bool
    );

    insert into public.account(id, is_verified)
    values
        (1, true),
        (2, true),
        (3, false);


    -- Filter by Int
    select jsonb_pretty(
        graphql.resolve($$
            {
              allAccounts(filter: {id: {eq: 2}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    -- Filter by Int and bool. has match
    select jsonb_pretty(
        graphql.resolve($$
            {
              allAccounts(filter: {id: {eq: 2}, isVerified: {eq: true}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    -- Filter by Int and bool. no match
    select jsonb_pretty(
        graphql.resolve($$
            {
              allAccounts(filter: {id: {eq: 2}, isVerified: {eq: false}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );


    -- Variable: value
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: AccountFilter)
           {
             allAccounts(filter: {id: {eq: $filt}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"filt": 2}'
      )
    );

rollback;
