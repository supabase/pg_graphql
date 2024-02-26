begin;
    -- https://github.com/supabase/pg_graphql/issues/237
    savepoint a;
    create table blog_post(
        id int primary key,
        a text,
        b text,
        c text,
        d text,
        e text,
        f text
    );
    insert into public.blog_post
    values (1, 'a', 'b', 'c', 'd', 'e', 'f');
    -- mismatched field names
    select jsonb_pretty(
      graphql.resolve($$
        query {
          blogPostCollection {
            edges {
              node {
                a
              }
            }
          }
          blogPostCollection {
            edges {
              node {
                a: b
              }
            }
          }
        }
      $$)
    );
    -- mismatched arguments
    select jsonb_pretty(
      graphql.resolve($$
        query {
          blogPostCollection(filter: {
            id: { eq: 1 }
          }) {
            edges {
              node {
                a
              }
            }
          }
          blogPostCollection {
            edges {
              node {
                b
              }
            }
          }
        }
      $$)
    );
    -- mismatched list to node
    select jsonb_pretty(
      graphql.resolve($$
        query {
          blogPostCollection {
            a: edges {
              cursor
            }
          }
          blogPostCollection {
            a: pageInfo {
              cursor: endCursor
            }
          }
        }
      $$)
    );

    rollback to savepoint a;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    insert into public.account(email)
    values
        ('aardvark@x.com');

    create table blog(
        id serial primary key,
        owner_id integer not null references account(id),
        name varchar(255) not null
    );

    insert into blog(owner_id, name)
    values
        (1, 'A: Blog 1');

    select jsonb_pretty(graphql.resolve($$ {
        accountCollection {
            edges {
                node {
                    email: id
                    email
                }
            }
        }
    }$$));

    select jsonb_pretty(graphql.resolve($$ {
        accountCollection(first: 1) {
            edges {
                node {
                    id
                    email
                }
            }
        }
        accountCollection(first: 2) {
            edges {
                node {
                    id
                    email
                }
            }
        }
    }$$));

    select jsonb_pretty(graphql.resolve($$ {
        accountCollection(first: $count) {
            edges {
                node {
                    id
                    email
                }
            }
        }
        accountCollection(first: 1) {
            edges {
                node {
                    id
                    email
                }
            }
        }
    }$$,
    jsonb_build_object(
        'count', 1
    )));

    select jsonb_pretty(graphql.resolve($$ {
        accountCollection(first: $count) {
            edges {
                node {
                    id
                    email
                }
            }
        }
        accountCollection(first: $num) {
            edges {
                node {
                    id
                    email
                }
            }
        }
    }$$,
    jsonb_build_object(
        'count', 1,
        'num', 1
    )));

    select jsonb_pretty(graphql.resolve($$ {
        accountCollection(first: 1) {
            edges {
                node {
                    id
                    email
                }
            }
        }
        accountCollection {
            edges {
                node {
                    id
                    email
                }
            }
        }
    }$$));

rollback;
