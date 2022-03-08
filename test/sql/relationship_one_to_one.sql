begin;
    create table account(
        id int primary key
    );

    create table address(
        id int primary key,
        -- unique constraint makes this a 1:1 relationship
        account_id int not null unique references account(id)
    );

    insert into account(id) select * from generate_series(1, 10);
    insert into address(id, account_id) select y.x, y.x from generate_series(1, 10) y(x);

    -- Filter by Int
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(filter: {id: {eq: 3}}) {
                edges {
                  node {
                    id
                    address {
                      id
                      account {
                        id
                        address {
                          id
                        }
                      }
                    }
                  }
                }
              }
            }
        $$)
    );
    rollback to savepoint a;

rollback;
