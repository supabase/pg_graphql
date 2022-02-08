begin;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    create table blog(
        id serial primary key,
        owner_id integer not null references account(id) on delete cascade,
        name varchar(255) not null
    );

    insert into public.account(email)
    values
        ('aardvark@x.com'),
        ('bat@x.com'),
        ('cat@x.com'),
        ('dog@x.com'),
        ('elephant@x.com');

    insert into blog(owner_id, name)
    values
        (1, 'A: Blog 1'),
        (1, 'A: Blog 2'),
        (2, 'A: Blog 3'),
        (2, 'B: Blog 3');

    savepoint a;

    -- Check atMost clause stops deletes
    select graphql.resolve($$
    mutation {
      deleteFromAccountCollection(
        filter: {
          email: {eq: "bat@x.com"}
        }
        atMost: 0
      ) {
        id
        email
        blogCollection {
          totalCount
          edges {
            node {
              id
            }
          }
        }
      }
    }
    $$);

    rollback to savepoint a;

    -- Check delete works and allows nested response
    select jsonb_pretty(
        graphql.resolve($$
            mutation {
              deleteFromAccountCollection(
                filter: {
                  email: {eq: "bat@x.com"}
                }
                atMost: 1
              ) {
                id
                email
                blogCollection {
                  totalCount
                  edges {
                    node {
                      id
                    }
                  }
                }
              }
            }
        $$)
    );

    rollback to savepoint a;

    -- Check no matches returns empty array vs null + allows top xyz alias
    select jsonb_pretty(
        graphql.resolve($$
            mutation {
              xyz: deleteFromAccountCollection(
                filter: {
                  email: {eq: "no@match.com"}
                }
                atMost: 1
              ) {
                id
              }
            }
        $$)
    );

rollback;
