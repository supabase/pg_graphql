begin;

    create table blog_post(
        id bigserial primary key,
        title text not null,
        parent_id bigint references blog_post(id)
    );

    select graphql.resolve($$
    mutation {
      insertIntoBlogPostCollection(objects: [{
        title: "hello"
        parentId: "1"
      }]) {
        affectedCount
        records {
          id
          parentId
        }
      }
    }
    $$);

    select graphql.resolve($$
    mutation {
      updateBlogPostCollection(set: {
        title: "xx"
      }) {
        affectedCount
        records {
          id
          parentId
        }
      }
    }
    $$);

    select graphql.resolve($$
    {
      blogPostCollection {
        totalCount
        edges {
          node {
            id
            parentId
            parent {
              id
              parentId
            }
          }
        }
      }
    }
    $$);

rollback;
