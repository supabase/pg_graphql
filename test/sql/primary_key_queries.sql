begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';
    savepoint a;

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

    savepoint b;

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

    rollback to savepoint b;

    -- Set up tables with relationships for connection and function tests
    create table author(
        id int primary key,
        name text not null
    );

    create table book(
        id int primary key,
        title text not null,
        author_id int references author(id)
    );

    insert into author(id, name)
    values
        (1, 'Jane Austen'),
        (2, 'Charles Dickens'),
        (3, 'Mark Twain');

    insert into book(id, title, author_id)
    values
        (1, 'Pride and Prejudice', 1),
        (2, 'Sense and Sensibility', 1),
        (3, 'Emma', 1),
        (4, 'Oliver Twist', 2),
        (5, 'Great Expectations', 2),
        (6, 'Adventures of Tom Sawyer', 3);

    -- Create a function that takes the author type as its first argument
    create function public._book_count(rec public.author)
        returns int
        stable
        language sql
    as $$
        select count(*)::int from book where author_id = rec.id
    $$;

    -- Create a function that returns text
    create function public._formatted_name(rec public.author)
        returns text
        immutable
        language sql
    as $$
        select 'Author: ' || rec.name
    $$;

    -- Test 12: nodeByPk with a nested function (scalar return)
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                bookCount
                formattedName
              }
            }
        $$)
    );

    -- Test 13: nodeByPk with a connection (one-to-many relationship)
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                bookCollection {
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 14: nodeByPk with connection and pagination
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                bookCollection(first: 2) {
                  pageInfo {
                    hasNextPage
                    hasPreviousPage
                  }
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 15: nodeByPk with connection filter
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                bookCollection(filter: {title: {like: "%Pride%"}}) {
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 16: nodeByPk with connection ordering
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                bookCollection(orderBy: [{title: DescNullsLast}]) {
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 17: nodeByPk with both function and connection
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 2) {
                id
                name
                bookCount
                formattedName
                bookCollection {
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 18: nodeByPk with nested relationship (book -> author)
    select jsonb_pretty(
        graphql.resolve($$
            {
              bookByPk(id: 1) {
                id
                title
                author {
                  id
                  name
                  bookCount
                }
              }
            }
        $$)
    );

    -- Test 19: nodeByPk with deeply nested connection
    select jsonb_pretty(
        graphql.resolve($$
            {
              bookByPk(id: 4) {
                id
                title
                author {
                  id
                  name
                  bookCollection {
                    edges {
                      node {
                        id
                        title
                      }
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 20: nodeByPk returning null with connection (non-existent author)
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 999) {
                id
                name
                bookCollection {
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 21: nodeByPk with empty connection (author with no books)
    insert into author(id, name) values (4, 'New Author');

    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 4) {
                id
                name
                bookCount
                bookCollection {
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 22: nodeByPk with function returning array type
    create function public._book_titles(rec public.author)
        returns text[]
        stable
        language sql
    as $$
        select array_agg(title) from book where author_id = rec.id
    $$;

    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                bookTitles
              }
            }
        $$)
    );

    -- Test 23: nodeByPk with function returning node type (single related record)
    create function public._latest_book(rec public.author)
        returns public.book
        stable
        language sql
    as $$
        select * from book where author_id = rec.id order by id desc limit 1
    $$;

    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                latestBook {
                  id
                  title
                }
              }
            }
        $$)
    );

    -- Test 24: nodeByPk with function returning node type, nested selection
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 2) {
                id
                name
                latestBook {
                  id
                  title
                  author {
                    id
                    name
                  }
                }
              }
            }
        $$)
    );

    -- Test 25: nodeByPk with function returning connection type (setof)
    create function public._popular_books(rec public.author)
        returns setof public.book
        stable
        language sql
    as $$
        select * from book where author_id = rec.id and id <= 2
    $$;

    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                popularBooks {
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 26: nodeByPk with function returning connection type with pagination
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                popularBooks(first: 1) {
                  pageInfo {
                    hasNextPage
                    hasPreviousPage
                  }
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 27: nodeByPk with function returning connection type with filter
    select jsonb_pretty(
        graphql.resolve($$
            {
              authorByPk(id: 1) {
                id
                name
                popularBooks(filter: {id: {eq: 1}}) {
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 28: Aliases work correctly with ByPk fields
    select jsonb_pretty(
        graphql.resolve($$
            {
              firstAuthor: authorByPk(id: 1) {
                id
                name
              }
              secondAuthor: authorByPk(id: 2) {
                id
                name
              }
            }
        $$)
    );

    -- Test 29: Nested aliases within ByPk queries
    select jsonb_pretty(
        graphql.resolve($$
            {
              myAuthor: authorByPk(id: 1) {
                authorId: id
                authorName: name
                books: bookCollection {
                  edges {
                    node {
                      bookId: id
                      bookTitle: title
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Test 30: ByPk fields are only exposed for tables with supported primary key types
    rollback to savepoint a;

    -- Create tables with various primary key configurations
    create table no_pk_table(value int);                        -- No primary key
    create table float_pk_table(id float primary key);          -- Unsupported: float
    create table bool_pk_table(id boolean primary key);         -- Unsupported: boolean
    create table bytea_pk_table(id bytea primary key);          -- Unsupported: bytea
    create table smallint_pk_table(id smallint primary key);    -- Supported: smallint
    create table bigint_pk_table(id bigint primary key);        -- Supported: bigint

    -- Query the schema to verify which tables have ByPk fields
    -- Expected ByPk fields: smallintPkTableByPk, bigintPkTableByPk
    -- Should NOT have: noPkTableByPk, floatPkTableByPk, boolPkTableByPk, byteaPkTableByPk
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Query") {
                fields {
                  name
                }
              }
            }
        $$)
    );

rollback;
