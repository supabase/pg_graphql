begin;
    -- Set up test tables with different primary key configurations
    
    -- Table with single column integer primary key
    create table person(
        id int primary key,
        name text,
        email text
    );

    insert into public.person(id, name, email)
    values
        (1, 'Alice', 'alice@example.com'),
        (2, 'Bob', 'bob@example.com'),
        (3, 'Charlie', null);

    -- Table with multi-column primary key
    create table item(
        item_id int,
        product_id int,
        quantity int,
        price numeric(10,2),
        primary key(item_id, product_id)
    );

    insert into item(item_id, product_id, quantity, price)
    values
        (1, 101, 2, 10.99),
        (1, 102, 1, 24.99),
        (2, 101, 3, 10.99),
        (3, 103, 5, 5.99);

    -- Table with text primary key (instead of UUID)
    create table document(
        id text primary key,
        title text,
        content text
    );

    insert into document(id, title, content)
    values
        ('doc-1', 'Document 1', 'Content 1'),
        ('doc-2', 'Document 2', 'Content 2');

    savepoint a;

    -- Test 1: Query a person by primary key (single integer column)
    select jsonb_pretty(
        graphql.resolve($$
            {
              personByPk(id: 1) {
                id
                name
                email
              }
            }
        $$)
    );

    -- Test 2: Query a person by primary key with relationship
    select jsonb_pretty(
        graphql.resolve($$
            {
              personByPk(id: 2) {
                id
                name
                email
                nodeId
              }
            }
        $$)
    );

    -- Test 3: Query a non-existent person by primary key
    select jsonb_pretty(
        graphql.resolve($$
            {
              personByPk(id: 999) {
                id
                name
              }
            }
        $$)
    );

    -- Test 4: Query with multi-column primary key
    select jsonb_pretty(
        graphql.resolve($$
            {
              itemByPk(itemId: 1, productId: 102) {
                itemId
                productId
                quantity
                price
              }
            }
        $$)
    );

    -- Test 5: Query with multi-column primary key, one column value is incorrect
    select jsonb_pretty(
        graphql.resolve($$
            {
              itemByPk(itemId: 1, productId: 999) {
                itemId
                productId
                quantity
                price
              }
            }
        $$)
    );

    -- Test 6: Query with text primary key
    select jsonb_pretty(
        graphql.resolve($$
            {
              documentByPk(id: "doc-1") {
                id
                title
                content
              }
            }
        $$)
    );

    -- Test 7: Using variables with primary key queries
    select jsonb_pretty(
        graphql.resolve($$
            query GetPerson($personId: Int!) {
              personByPk(id: $personId) {
                id
                name
                email
              }
            }
        $$, '{"personId": 3}')
    );

    -- Test 8: Using variables with multi-column primary key queries
    select jsonb_pretty(
        graphql.resolve($$
            query GetItem($itemId: Int!, $productId: Int!) {
              itemByPk(itemId: $itemId, productId: $productId) {
                itemId
                productId
                quantity
                price
              }
            }
        $$, '{"itemId": 2, "productId": 101}')
    );

    -- Test 9: Error case - missing required primary key column
    select jsonb_pretty(
        graphql.resolve($$
            {
              itemByPk(itemId: 1) {
                itemId
                productId
              }
            }
        $$)
    );

    -- Test 10: Using fragments with primary key queries
    select jsonb_pretty(
        graphql.resolve($$
            {
              personByPk(id: 1) {
                ...PersonFields
              }
            }
            
            fragment PersonFields on Person {
              id
              name
              email
            }
        $$)
    );

    -- Test 11: Query with null values in results
    select jsonb_pretty(
        graphql.resolve($$
            {
              personByPk(id: 3) {
                id
                name
                email
              }
            }
        $$)
    );

rollback; 