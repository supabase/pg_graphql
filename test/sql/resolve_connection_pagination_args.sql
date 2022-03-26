begin;
    create table account(
        id int primary key
    );
    comment on table account is e'@graphql({"totalCount": {"enabled": true}})';


    insert into public.account(id)
    select * from generate_series(1,5);


    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 2, after: "WyJhY2NvdW50IiwgM10=") {
                totalCount
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    -- First without an after clause
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 2) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    -- First with after = null same as omitting after
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 2, after: null) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    -- First with after = null as variable same as omitting after
    select jsonb_pretty(
        graphql.resolve($$
            query ABC($afterCursor: Cursor){
              accountCollection(first: 2, after: $afterCursor) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$,
        variables := '{"afterCursor": null}'
    ));

    -- last before
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(last: 2, before: "WyJhY2NvdW50IiwgM10=") {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    -- Last without a before clause
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(last: 2) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    /*
    ERROR STATES
    */

    -- first + last raises an error
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 2, last: 1) {
                totalCount
              }
            }
        $$)
    );

    -- before + after raises an error
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(before: "WyJhY2NvdW50IiwgM10=", after: "WyJhY2NvdW50IiwgM10=") {
                totalCount
              }
            }
        $$)
    );

    -- first + before raises an error
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 2, before: "WyJhY2NvdW50IiwgM10=") {
                totalCount
              }
            }
        $$)
    );

    -- last + after raises an error
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(last: 2, after: "WyJhY2NvdW50IiwgM10=") {
                totalCount
              }
            }
        $$)
    );


rollback;
