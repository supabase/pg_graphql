begin;

    -- Table with non-serial primary key (supports upsert)
    create table account(
        id int primary key,
        email varchar(255) not null,
        name text,
        status text default 'active'
    );

    -- Table with serial primary key (should NOT support upsert on pkey)
    create table blog(
        id serial primary key,
        owner_id integer not null references account(id),
        title text not null
    );

    -- Table with composite unique constraint
    create table account_setting(
        account_id int references account(id),
        setting_key text not null,
        setting_value text,
        primary key (account_id, setting_key)
    );

    -- Table with additional unique index
    create table product(
        id int primary key,
        sku text not null unique,
        name text,
        price numeric
    );

    -- Insert initial data
    insert into account(id, email, name, status) values
        (1, 'alice@example.com', 'Alice', 'active'),
        (2, 'bob@example.com', 'Bob', 'active');

    insert into account_setting(account_id, setting_key, setting_value) values
        (1, 'theme', 'dark'),
        (1, 'notifications', 'enabled');

    insert into product(id, sku, name, price) values
        (1, 'SKU001', 'Widget', 9.99),
        (2, 'SKU002', 'Gadget', 19.99);

    /*
        Check that onConflict argument is available for tables with non-serial unique constraints
    */

    -- Account table should have onConflict (non-serial primary key)
    select jsonb_pretty(graphql.resolve($$
    {
      __type(name: "Mutation") {
        fields {
          name
          args {
            name
            type {
              name
              kind
            }
          }
        }
      }
    }
    $$) -> 'data' -> '__type' -> 'fields') @> '[{"name": "insertIntoAccountCollection", "args": [{"name": "onConflict"}]}]'::jsonb;

    -- Blog table should NOT have onConflict (serial primary key)
    select not (jsonb_pretty(graphql.resolve($$
    {
      __type(name: "Mutation") {
        fields {
          name
          args {
            name
          }
        }
      }
    }
    $$) -> 'data' -> '__type' -> 'fields') @> '[{"name": "insertIntoBlogCollection", "args": [{"name": "onConflict"}]}]'::jsonb);

    /*
        Basic upsert - insert new record
    */

    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [{ id: 3, email: "charlie@example.com", name: "Charlie" }]
        onConflict: {
          constraint: account_pkey
          updateColumns: [email, name]
        }
      ) {
        affectedCount
        records {
          id
          email
          name
          status
        }
      }
    }
    $$);

    /*
        Basic upsert - update existing record
    */

    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [{ id: 1, email: "alice_updated@example.com", name: "Alice Updated" }]
        onConflict: {
          constraint: account_pkey
          updateColumns: [email, name]
        }
      ) {
        affectedCount
        records {
          id
          email
          name
          status
        }
      }
    }
    $$);

    -- Verify the update happened
    select id, email, name from account where id = 1;

    /*
        Upsert with partial update columns - only update specific fields
    */

    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [{ id: 2, email: "bob_new@example.com", name: "Bob New Name", status: "inactive" }]
        onConflict: {
          constraint: account_pkey
          updateColumns: [name]
        }
      ) {
        affectedCount
        records {
          id
          email
          name
          status
        }
      }
    }
    $$);

    -- Verify only name was updated, email and status unchanged
    select id, email, name, status from account where id = 2;

    /*
        Upsert with filter clause - conditional update
    */

    -- Reset Bob's data first
    update account set email = 'bob@example.com', name = 'Bob', status = 'active' where id = 2;

    -- This should NOT update because filter doesn't match (status is 'active', not 'pending')
    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [{ id: 2, email: "should_not_update@example.com", name: "Should Not Update" }]
        onConflict: {
          constraint: account_pkey
          updateColumns: [email, name]
          filter: { status: { eq: "pending" } }
        }
      ) {
        affectedCount
        records {
          id
          email
          name
        }
      }
    }
    $$);

    -- Verify Bob's data is unchanged
    select id, email, name from account where id = 2;

    -- This SHOULD update because filter matches (status is 'active')
    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [{ id: 2, email: "bob_filtered@example.com", name: "Bob Filtered" }]
        onConflict: {
          constraint: account_pkey
          updateColumns: [email, name]
          filter: { status: { eq: "active" } }
        }
      ) {
        affectedCount
        records {
          id
          email
          name
        }
      }
    }
    $$);

    -- Verify Bob's data was updated
    select id, email, name from account where id = 2;

    /*
        Upsert with composite primary key
    */

    select graphql.resolve($$
    mutation {
      insertIntoAccountSettingCollection(
        objects: [{ accountId: 1, settingKey: "theme", settingValue: "light" }]
        onConflict: {
          constraint: account_setting_pkey
          updateColumns: [settingValue]
        }
      ) {
        affectedCount
        records {
          accountId
          settingKey
          settingValue
        }
      }
    }
    $$);

    -- Verify the setting was updated
    select account_id, setting_key, setting_value from account_setting where account_id = 1 and setting_key = 'theme';

    /*
        Upsert using unique constraint (not primary key)
    */

    select graphql.resolve($$
    mutation {
      insertIntoProductCollection(
        objects: [{ id: 10, sku: "SKU001", name: "Widget Pro", price: 14.99 }]
        onConflict: {
          constraint: product_sku_key
          updateColumns: [name, price]
        }
      ) {
        affectedCount
        records {
          id
          sku
          name
          price
        }
      }
    }
    $$);

    -- Verify the product was updated (not inserted with id 10)
    select id, sku, name, price from product where sku = 'SKU001';

    /*
        Upsert with variables
    */

    select graphql.resolve($$
    mutation UpsertAccount($id: Int!, $email: String!, $name: String, $constraint: AccountConstraint!, $cols: [AccountUpdateColumn!]!) {
      insertIntoAccountCollection(
        objects: [{ id: $id, email: $email, name: $name }]
        onConflict: {
          constraint: $constraint
          updateColumns: $cols
        }
      ) {
        affectedCount
        records {
          id
          email
          name
        }
      }
    }
    $$,
    variables := '{"id": 1, "email": "alice_var@example.com", "name": "Alice Variable", "constraint": "account_pkey", "cols": ["email", "name"]}'::jsonb
    );

    -- Verify
    select id, email, name from account where id = 1;

    /*
        Multiple records upsert
    */

    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [
          { id: 1, email: "alice_multi@example.com", name: "Alice Multi" },
          { id: 5, email: "eve@example.com", name: "Eve" }
        ]
        onConflict: {
          constraint: account_pkey
          updateColumns: [email, name]
        }
      ) {
        affectedCount
        records {
          id
          email
          name
        }
      }
    }
    $$);

    /*
        Error cases
    */

    -- Invalid constraint name
    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [{ id: 1, email: "test@test.com" }]
        onConflict: {
          constraint: invalid_constraint_name
          updateColumns: [email]
        }
      ) {
        affectedCount
      }
    }
    $$);

    -- Empty updateColumns (should still work - do nothing on conflict effectively)
    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(
        objects: [{ id: 1, email: "test@test.com" }]
        onConflict: {
          constraint: account_pkey
          updateColumns: []
        }
      ) {
        affectedCount
      }
    }
    $$);

rollback;
