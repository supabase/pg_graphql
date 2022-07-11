begin;
    create table states(
        id int primary key,
        country_code char(2)
    );

    insert into public.states(id, country_code)
    values
        (1, 'GB'),
        (2, 'CH');

    savepoint a;

    -- Filter by Int
    select jsonb_pretty(
        graphql.resolve($$
            {
              statesCollection(filter: {id: {eq: 2}}) {
                edges {
                  node {
                    id
                    countryCode
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
              accountCollection(filter: {countryCode: {eq: 'GB'}) {
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

rollback;
