begin;
    create table account(
        id int primary key
    );

    insert into public.account(id)
    select * from generate_series(1,5);

    -- hasPreviousPage is false when `after` is first element of collection
    -- "WzFd" is id=1

    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 2, after: "WzFd") {
                pageInfo{
                  hasPreviousPage
                }
              }
            }
        $$)
    );
rollback;
