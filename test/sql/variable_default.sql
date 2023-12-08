begin;

    create table blog(
        id int primary key
    );

    insert into blog(id)
    select generate_series(1, 5);

    -- User defined default for variable $first.

    -- Returns 2 rows
    -- No value provided for variable $first so user defined default applies
    select graphql.resolve($$
        query Blogs($first: Int = 2) {
          blogCollection(first: $first) {
            edges {
              node {
                id
              }
            }
          }
        }
    $$);

    -- Returns 1 row
    -- Provided value for variable $first applies
    select graphql.resolve($$
        query Blogs($first: Int = 2) {
          blogCollection(first: $first) {
            edges {
              node {
                id
              }
            }
          }
        }
      $$,
      variables := jsonb_build_object(
        'first', 1
      )
    );

    -- Returns all rows
    -- No default, no variable value. Falls back to sever side behavior
    select graphql.resolve($$
        query Blogs($first: Int) {
          blogCollection(first: $first) {
            edges {
              node {
                id
              }
            }
          }
        }
      $$
    );

rollback;
