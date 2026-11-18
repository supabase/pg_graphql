begin;

    create table blog_post(
        id bigserial primary key,
        title text not null,
        parent_id bigint references blog_post(id)
    );
    comment on table blog_post is e'@graphql({"totalCount": {"enabled": true}})';

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

    -- BigInt input must be a decimal integer in the int8 range
    select
        v,
        graphql.resolve(
            $$query ($v: BigInt) { blogPostCollection(filter: {parentId: {eq: $v}}) { totalCount } }$$,
            variables := jsonb_build_object('v', v)
        )
    from (
        values
            ('"not-an-int"'::jsonb),
            ('"1.5"'),
            ('1.5'),
            ('"0x10"'),
            ('"1_000"'),
            ('"9223372036854775808"'),
            ('"-9223372036854775809"'),
            ('9223372036854775808'),
            ('"9223372036854775807"'),
            ('"-9223372036854775808"'),
            ('"1"'),
            ('" 1 "'),
            ('1')
    ) t(v);

    select graphql.resolve($$
    mutation {
      insertIntoBlogPostCollection(objects: [{
        title: "hello"
        parentId: "one"
      }]) {
        affectedCount
      }
    }
    $$);

    select graphql.resolve($$
    mutation {
      updateBlogPostCollection(set: {
        parentId: 1.5
      }) {
        affectedCount
      }
    }
    $$);

    select graphql.resolve($$
    mutation {
      deleteFromBlogPostCollection {
        affectedCount
        records {
          id
          parentId
        }
      }
    }
    $$);

rollback;
