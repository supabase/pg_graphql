begin;
    create table account(
        id int primary key,
        category text
    );

    insert into public.account(id, category)
    values
        (1, 'a'),
        (2, 'b'),
        (3, 'c');

    create function list_accounts()
        returns setof account
        stable
        language sql
    as $$
        select * from account;
    $$;

    -- Table collection ignores the filter when the variable is omitted
    select jsonb_pretty(
        graphql.resolve($$
            query Accounts($category: String) {
              accountCollection(filter: {category: {eq: $category}}) {
                edges {
                  node {
                    id
                    category
                  }
                }
              }
            }
        $$,
        variables := '{}'
        )
    );

    -- Function collection should do the same
    select jsonb_pretty(
        graphql.resolve($$
            query Accounts($category: String) {
              listAccounts(filter: {category: {eq: $category}}) {
                edges {
                  node {
                    id
                    category
                  }
                }
              }
            }
        $$,
        variables := '{}'
        )
    );

    -- Function collection applies the filter when the variable is set
    select jsonb_pretty(
        graphql.resolve($$
            query Accounts($category: String) {
              listAccounts(filter: {category: {eq: $category}}) {
                edges {
                  node {
                    id
                    category
                  }
                }
              }
            }
        $$,
        variables := '{"category": "b"}'
        )
    );
rollback;
