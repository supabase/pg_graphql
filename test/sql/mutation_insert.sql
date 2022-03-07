begin;

    create table account(
        id serial primary key,
        email varchar(255) not null,
        priority int
    );

    create table blog(
        id serial primary key,
        owner_id integer not null references account(id)
    );
    comment on table blog is e'@graphql({"totalCount": {"enabled": true}})';

    -- Make sure functions still work
    create function _echo_email(account)
        returns text
        language sql
    as $$ select $1.email $$;

    /*
        Literals
    */

    select graphql.resolve($$
    mutation {
      insertIntoAccountCollection(objects: [
        { email: "foo@barsley.com", priority: 1 },
        { email: "bar@foosworth.com" }
      ]) {
        affectedCount
        records {
          id
          echoEmail
          blogCollection {
            totalCount
          }
        }
      }
    }
    $$);

    select graphql.resolve($$
    mutation {
      insertIntoBlogCollection(objects: [{
        ownerId: 1
      }]) {
        records {
          id
          owner {
            id
          }
        }
      }
    }
    $$);

    /*
        Variables
    */

    select graphql.resolve($$
    mutation newAccount($emailAddress: String) {
       xyz: insertIntoAccountCollection(objects: [
        { email: $emailAddress },
        { email: "other@email.com" }
       ]) {
        affectedCount
        records {
          id
          email
        }
      }
    }
    $$,
    variables := '{"emailAddress": "foo@bar.com"}'::jsonb
    );


    select graphql.resolve($$
    mutation newAccount($acc: AccountInsertInput!) {
       insertIntoAccountCollection(objects: [$acc]) {
        affectedCount
        records {
          id
          email
        }
      }
    }
    $$,
    variables := '{"acc": {"email": "bar@foo.com"}}'::jsonb
    );

    select graphql.resolve($$
    mutation newAccounts($acc: [AccountInsertInput!]!) {
       insertIntoAccountCollection(objects: $accs) {
        affectedCount
        records {
          id
          email
        }
      }
    }
    $$,
    variables := '{"accs": [{"email": "bar@foo.com"}]}'::jsonb
    );

    /*
        Errors
    */

    -- Field does not exist
    select graphql.resolve($$
    mutation createAccount($acc: AccountInsertInput) {
       insertIntoAccountCollection(objects: [$acc]) {
        affectedCount
        records {
          id
          email
        }
      }
    }
    $$,
    variables := '{"acc": {"doesNotExist": "other"}}'::jsonb
    );

    -- Wrong input type (object vs list)
    select graphql.resolve($$
    mutation {
      insertIntoBlogCollection(objects: {ownerId: 1}) {
        affectedCount
      }
    }
    $$);

    -- Wrong input type (list of string, not list of object)
    select graphql.resolve($$
    mutation {
      insertIntoBlogCollection(objects: ["not an object"]) {
        affectedCount
      }
    }
    $$);

    -- objects argument is missing
    select graphql.resolve($$
    mutation {
      insertIntoBlogCollection {
        affectedCount
      }
    }
    $$);

    -- Empty call
    select graphql.resolve($$
    mutation {
      insertIntoBlogCollection(objects: []) {
        affectedCount
      }
    }
    $$);

rollback;
