begin;
    create table account(
        id int primary key,
        is_verified bool,
        name text,
        phone text
    );

    insert into public.account(id, is_verified, name, phone)
    values
        (1, true, 'foo', '1111111111'),
        (2, true, 'bar', null),
        (3, false, 'baz', '33333333333');

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

    -- Filter is null should have no effect
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(filter: null) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    -- filter = null is ignored
    select graphql.resolve($${accountCollection(filter: null) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- neq
    select graphql.resolve($${accountCollection(filter: {id: {neq: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- lt
    select graphql.resolve($${accountCollection(filter: {id: {lt: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- lt - null - treated as literal
    select graphql.resolve($${accountCollection(filter: {id: {lt: null}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- lte
    select graphql.resolve($${accountCollection(filter: {id: {lte: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- gte
    select graphql.resolve($${accountCollection(filter: {id: {gte: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- gt
    select graphql.resolve($${accountCollection(filter: {id: {gt: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- is - is null
    select graphql.resolve($${accountCollection(filter: {phone: {is: NULL}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- is - is not null
    select graphql.resolve($${accountCollection(filter: {phone: {is: NOT_NULL}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- is - invalid input
    select graphql.resolve($${accountCollection(filter: {phone: {is: INVALID}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- is - null literal returns error (this may change but currently seems like the best option and "unbreaking" it is backwards compatible)
    select graphql.resolve($${accountCollection(filter: {phone: {is: null}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- variable is - is null
    select graphql.resolve($$query AAA($nis: FilterIs) { accountCollection(filter: {phone: {is: $nis}}) { edges { node { id } } }}$$, '{"nis": "NULL"}');
    rollback to savepoint a;

    -- variable is - absent treated as ignored / returns all
    select graphql.resolve($$query AAA($nis: FilterIs) { accountCollection(filter: {phone: {is: $nis}}) { edges { node { id } } }}$$, '{}');
    rollback to savepoint a;

    -- in - int
    select graphql.resolve($${accountCollection(filter: {id: {in: [1, 2]}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- nin - int
    select graphql.resolve($${accountCollection(filter: {id: {nin: [1, 2]}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - int coerce to list
    select graphql.resolve($${accountCollection(filter: {id: {in: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- nin - int coerce to list
    select graphql.resolve($${accountCollection(filter: {id: {nin: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - text
    select graphql.resolve($${accountCollection(filter: {name: {in: ["foo", "bar"]}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- nin - text
    select graphql.resolve($${accountCollection(filter: {name: {nin: ["foo", "bar"]}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - text coerce to list
    select graphql.resolve($${accountCollection(filter: {name: {in: "baz"}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- nin - text coerce to list
    select graphql.resolve($${accountCollection(filter: {name: {nin: "baz"}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - empty list
    select graphql.resolve($${accountCollection(filter: {name: {in: []}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- nin - empty list
    select graphql.resolve($${accountCollection(filter: {name: {nin: []}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - null literal returns nothing
    select graphql.resolve($${accountCollection(filter: {name: {in: null}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- nin - null literal returns nothing
    select graphql.resolve($${accountCollection(filter: {name: {nin: null}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- variable in - absent treated as ignored / returns all
    select graphql.resolve($$query AAA($nin: [String!]) { accountCollection(filter: {name: {in: $nin}}) { edges { node { id } } }}$$, '{}');
    rollback to savepoint a;

    -- Variable: In, mixed List Int
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: Int!)
           {
             accountCollection(filter: {id: {in: [1, $filt]}}) {
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
    rollback to savepoint a;

    -- Variable: In: single elem wrapped in list
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: Int!)
           {
             accountCollection(filter: {id: {in: [$filt]}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"filt": 3}'
      )
    );
    rollback to savepoint a;

    -- Variable: In: single elem coerce to list
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: Int!)
           {
             accountCollection(filter: {id: {in: $filt}}) {
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

    -- Variable: In: multi-element list
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: [Int!])
           {
             accountCollection(filter: {id: {in: $filt}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"filt": [2, 3]}'
      )
    );
    rollback to savepoint a;

    -- Variable: In: variables not an object
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: [Int!])
           {
             accountCollection(filter: {id: {in: $filt}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '[{"filt": [2, 3]}]'
      )
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

    -- Variable: AccountFilter, null does not apply any filters
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
        variables:= '{"afilt": null }'
      )
    );
    rollback to savepoint a;

rollback;
