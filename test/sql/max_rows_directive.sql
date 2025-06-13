begin;
    create table account(
        id int primary key
    );

    insert into public.account(id)
    select * from generate_series(1, 100);

    -- expect default 30 rows on first page
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

    comment on schema public is e'@graphql({"max_rows": 5})';

    -- expect 5 rows on first page
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

    comment on schema public is e'@graphql({"max_rows": 40})';

    -- expect 40 rows on first page
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

    -- table-specific max_rows
    comment on table account is e'@graphql({"max_rows": 5})';

    -- expect 5 rows on first page
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
    create view person as
    select * from account;
    comment on view person is e'@graphql({"primary_key_columns": ["id"], "max_rows": 3})';

    -- expect 3 rows on first page
    select graphql.resolve($$
      {
        personCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

    -- nested view with max_rows
    create view parent as
    select * from person;
    comment on view parent is e'@graphql({"primary_key_columns": ["id"], "max_rows": 2})';

    -- expect 2 rows on first page
    select graphql.resolve($$
      {
        parentCollection {
          edges {
            node {
              id
            }
          }
        }
      }
    $$);

rollback;
