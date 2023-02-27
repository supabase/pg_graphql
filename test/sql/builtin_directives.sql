begin;
    create table book(
        id int primary key,
        is_verified bool
    );

    insert into public.book(id, is_verified)
    values
        (1, true);

    savepoint a;

    -- Should be skipped
    select jsonb_pretty(
        graphql.resolve($$
            {
              bookCollection {
                edges {
                  node {
                    id
                    isVerified @skip( if: true )
                  }
                }
              }
            }
        $$)
    );

    -- Should not be skipped
    select jsonb_pretty(
        graphql.resolve($$
            {
              bookCollection {
                edges {
                  node {
                    id
                    isVerified @skip( if: false )
                  }
                }
              }
            }
        $$)
    );


    select jsonb_pretty(
        graphql.resolve($$
            query XXX($should_skip: Boolean! ){
              bookCollection{
                edges {
                  node {
                    id
                    isVerified @skip(if: $should_skip)
                  }
                }
              }
            }
          $$,
          '{"should_skip": true}'
        )
    );

    select jsonb_pretty(
        graphql.resolve($$
            query XXX($should_skip: Boolean! ){
              bookCollection{
                edges {
                  node {
                    id
                    isVerified @skip(if: $should_skip)
                  }
                }
              }
            }
          $$,
          '{"should_skip": false}'
        )
    );

rollback;
