begin;

    create table account(
        id serial primary key,
        parent_id int references account(id)
    );

    -- A composite field selected with no subfields must be rejected, not
    -- silently resolved. See https://github.com/supabase/pg_graphql/issues/412

    -- top level connection
    select graphql.resolve($$
    {
      accountCollection
    }
    $$);

    -- nested edges
    select graphql.resolve($$
    {
      accountCollection {
        edges
      }
    }
    $$);

    -- nested node
    select graphql.resolve($$
    {
      accountCollection {
        edges {
          node
        }
      }
    }
    $$);

    -- node by primary key
    select graphql.resolve($$
    {
      accountByPk(id: 1)
    }
    $$);

    -- mutation payload
    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(objects: [{ }])
    }
    $$);

    -- a field skipped away at the top level still reports the empty operation
    -- selection set, unchanged by the above
    select graphql.resolve($$
    {
      accountCollection @skip(if: true)
    }
    $$);

rollback;
