begin;
    -- https://github.com/supabase/pg_graphql/issues/237
    create table blog_post(
        id int primary key,
        a text,
        b text,
        c text,
        d text,
        e text,
        f text
    );
    insert into public.blog_post
    values (1, 'a', 'b', 'c', 'd', 'e', 'f');
    -- mismatched field names
    select jsonb_pretty(
      graphql.resolve($$
        query {
          blogPostCollection {
            edges {
              node {
                a
              }
            }
          }
          blogPostCollection {
            edges {
              node {
                a: b
              }
            }
          }
        }
      $$)
    );
    -- mismatched arguments
    select jsonb_pretty(
      graphql.resolve($$
        query {
          blogPostCollection(filter: {
            id: { eq: 1 }
          }) {
            edges {
              node {
                a
              }
            }
          }
          blogPostCollection {
            edges {
              node {
                b
              }
            }
          }
        }
      $$)
    );
    -- mismatched list to node
    select jsonb_pretty(
      graphql.resolve($$
        query {
          blogPostCollection {
            a: edges {
              cursor
            }
          }
          blogPostCollection {
            a: pageInfo {
              cursor: endCursor
            }
          }
        }
      $$)
    );
rollback;
