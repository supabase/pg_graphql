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
              accountCollection(filter: {id: {eq: 2}}) {
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
              accountCollection(filter: {id: {eq: 2}, isVerified: {eq: true}}) {
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
              accountCollection(filter: {id: {eq: 2}, isVerified: {eq: false}}) {
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
             accountCollection(filter: {id: {eq: $filt}}) {
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
             accountCollection(filter: {id: $ifilt}) {
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

    -- Variable: AccountFilter, single col
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": {"eq": 2}} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, multi col match
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": {"eq": 2}, "isVerified": {"eq": true}} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, multi col no match
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": {"eq": 2}, "isVerified": {"eq": false}} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, invalid field name
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"dne_id": 2} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, invalid IntFilter
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": 2} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, invalid data type
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": {"eq": true}} }'
      )
    );
    rollback to savepoint a;

rollback;
