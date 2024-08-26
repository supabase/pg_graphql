begin;

    create table account(
        id int primary key,
        email varchar(255) not null,
        priority int,
        status text default 'active'
    );

    /*
        Literals
    */

    select jsonb_pretty(graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [
          { id: 1, email: "foo@barsley.com", priority: 1 },
          { id: 2, email: "bar@foosworth.com" }
        ]
        onConflict: {
          constraint: account_pkey,
          updateFields: [email, priority, status],
        }
    ) {
        affectedCount
        records {
          id
          email
          priority
        }
      }
    }
    $$));

    -- Email should update. Priority should not
    -- 1 row affected
    select jsonb_pretty(graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [
          { id: 1, email: "new@email.com", priority: 2 },
        ]
        onConflict: {
          constraint: account_pkey,
          updateFields: [email, status],
        }
    ) {
        affectedCount
        records {
          id
          email
        }
      }
    }
    $$));

    -- Email and priority should update
    -- 2 row affected
    select jsonb_pretty(graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [
          { id: 1, email: "new@email.com", priority: 2 },
          { id: 2, email: "new@email.com"},
        ]
        onConflict: {
          constraint: account_pkey,
          updateFields: [email, status],
        }
    ) {
        affectedCount
        records {
          id
          email
          priority
        }
      }
    }
    $$));

    -- Filter prevents second row update
    -- 1 row affected
    select jsonb_pretty(graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [
          { id: 1, email: "third@email.com"},
          { id: 2, email: "new@email.com"},
        ]
        onConflict: {
          constraint: account_pkey,
          updateFields: [email, status],
        }
        filter: {
          id: {id: $ifilt}
        }
    ) {
        affectedCount
        records {
          id
          email
          priority
        }
      }
    }
    $$));

    -- Variable Filter
    -- Only row id=2 updated due to where clause
    select jsonb_pretty(graphql.resolve($$
    mutation AccountsFiltered($ifilt: IntFilter!)
      insertIntoAccountCollection(
        objects: [
          { id: 1, email: "fourth@email.com"},
          { id: 2, email: "fourth@email.com"},
        ]
        onConflict: {
          constraint: account_pkey,
          updateFields: [email, status],
        }
        filter: {
          id: {id: $ifilt}
        }
    ) {
        affectedCount
        records {
          id
          email
          priority
        }
      }
    }
    $$,
    variables:= '{"ifilt": {"eq": 2}}'
    ));

rollback;
