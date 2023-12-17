begin;
    -- https://github.com/supabase/pg_graphql/issues/237
    create table blog_post(
        id int primary key,
        title text not null,
        content text
    );
    insert into public.blog_post(id, title, content)
    values
      (1, 'A: Blog 1', 'Lorem ipsum');
    select jsonb_pretty(
      graphql.resolve($$
        query {
          blogPostCollection {
            edges {
              node {
                id
                title
              }
            }
          }
          blogPostCollection {
            edges {
              node {
                content
              }
            }
          }
        }
      $$)
    );
rollback;
