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

    savepoint a;

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
    rollback to savepoint a;

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
    rollback to savepoint a;

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
    rollback to savepoint a;


    -- Variable: Int
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: Int!)
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
        variables:= '{"filt": 1}'
      )
    );
    rollback to savepoint a;

    -- Variable: IntFilter
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($ifilt: IntFilter!)
           {
             allAccounts(filter: {id: $ifilt}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"ifilt": {"eq": 3}}'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             allAccounts(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"ifilt": {"id": {"eq": 1}} }'
      )
    );
    rollback to savepoint a;

rollback;
