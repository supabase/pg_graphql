begin;

    create table account(
        id int primary key,
        parent_id int references account(id)
    );

    insert into public.account(id, parent_id)
    values
        (1, 1);


    select jsonb_pretty(
        graphql.resolve($$
    query Abc {
      __typename
      accountCollection {
        __typename
        pageInfo {
          __typename
        }
        edges {
          __typename
          node {
            __typename
            parent {
              __typename
            }
          }
        }
      }
    }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
    mutation Abc {
      __typename
      insertIntoAccountCollection(objects: [
        { id: 2, parentId: 1 }
      ]) {
        __typename
        records {
          __typename
        }
      }
    }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
    mutation {
      updateAccountCollection(
        set: { parentId: 1 }
        atMost: 100
      ) {
        __typename
        records {
          id
          __typename
        }
      }
    }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
    mutation {
      deleteFromAccountCollection(atMost: 100) {
        __typename
        records {
          __typename
        }
      }
    }
        $$)
    );

    -- Reset data for byPk tests
    insert into public.account(id, parent_id)
    values
        (1, 1),
        (2, 1);

    -- Test __typename with byPk query
    select jsonb_pretty(
        graphql.resolve($$
    query {
      accountByPk(id: 1) {
        __typename
        id
        parent {
          __typename
          id
        }
      }
    }
        $$)
    );

    -- Test __typename with multi-column primary key
    create table order_item(
        order_id int,
        item_id int,
        quantity int,
        primary key (order_id, item_id)
    );

    insert into public.order_item(order_id, item_id, quantity)
    values
        (100, 1, 5),
        (100, 2, 3);

    select jsonb_pretty(
        graphql.resolve($$
    query {
      orderItemByPk(orderId: 100, itemId: 1) {
        __typename
        orderId
        itemId
        quantity
      }
    }
        $$)
    );

    -- Test __typename with non-int primary key
    create table product(
        sku text primary key,
        name text
    );

    insert into public.product(sku, name)
    values
        ('PROD-001', 'Widget'),
        ('PROD-002', 'Gadget');

    select jsonb_pretty(
        graphql.resolve($$
    query {
      productByPk(sku: "PROD-001") {
        __typename
        sku
        name
      }
    }
        $$)
    );

    -- Test __typename with byPk query returning null
    select jsonb_pretty(
        graphql.resolve($$
    query {
      accountByPk(id: 999) {
        __typename
        id
      }
    }
        $$)
    );

rollback;
