begin;
    create table account(
        id int primary key
    );

    create view "accountView" as
    select * from account;
    comment on view "accountView" is e'@graphql({"primary_key_columns": ["id"]})';

    create view "accountViewWrapper" as
    select * from "accountView";
    comment on view "accountViewWrapper" is e'@graphql({"primary_key_columns": ["id"]})';

    insert into public.account(id)
    select * from generate_series(1, 100);

    -- expect 30 rows on first page because of fallback to default
    select graphql.resolve($$
      {
        accountCollection
        {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- expect 30 rows on first page because of fallback to default
    select graphql.resolve($$
      {
        accountViewCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- expect 30 rows on first page because of fallback to default
    select graphql.resolve($$
      {
        accountViewWrapperCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    comment on schema public is e'@graphql({"max_rows": 5})';

    -- expect 5 rows on first page because of fallback to schema max_rows
    select graphql.resolve($$
      {
        accountCollection
        {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- expect 5 rows on first page because of fallback to schema max_rows
    select graphql.resolve($$
      {
        accountViewCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- expect 5 rows on first page because of fallback to schema max_rows
    select graphql.resolve($$
      {
        accountViewWrapperCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    comment on schema public is e'@graphql({"max_rows": 40})';

    -- expect 40 rows on first page because of fallback to schema max_rows
    select graphql.resolve($$
      {
        accountCollection
        {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- expect 40 rows on first page because of fallback to schema max_rows
    select graphql.resolve($$
      {
        accountViewCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- expect 40 rows on first page because of fallback to schema max_rows
    select graphql.resolve($$
      {
        accountViewWrapperCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- table-specific max_rows
    comment on table account is e'@graphql({"max_rows": 5})';

    -- expect 5 rows on first page because of table max_rows
    select graphql.resolve($$
      {
        accountCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- view-specific max_rows
    comment on view "accountView" is e'@graphql({"primary_key_columns": ["id"], "max_rows": 3})';

    -- expect 3 rows on first page because of view max_rows
    select graphql.resolve($$
      {
        accountViewCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- nested view with max_rows
    comment on view "accountViewWrapper" is e'@graphql({"primary_key_columns": ["id"], "max_rows": 2})';

    -- expect 2 rows on first page because of view max_rows
    select graphql.resolve($$
      {
        accountViewWrapperCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

rollback;
