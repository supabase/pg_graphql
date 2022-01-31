begin;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    insert into public.account(email)
    values
        ('aardvark@x.com');

    create table blog(
        id serial primary key,
        owner_id integer not null references account(id)
    );

    -- Make sure functions still work
    create function _echo_email(account)
        returns text
        language sql
    as $$ select $1.email $$;


    select graphql.resolve($$
    mutation {
      insertAccount(object: {
        email: "foo@barsley.com"
      }) {
        id
        nodeId
        echoEmail
        blogCollection {
            totalCount
        }
      }
    }
    $$);

    select * from account;


    select graphql.resolve($$
    mutation {
      insertBlog(object: {
        ownerId: 2
      }) {
        id
        nodeId
        owner {
          id
        }
      }
    }
    $$);

    select * from blog;



rollback;
