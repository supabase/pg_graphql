begin;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    select graphql.resolve($$
    mutation newAccount($emailAddress: String) {
       xyz: createAccount(objects: [{
        email: $emailAddress
      }]) {
        affectedCount
        results {
          id
          email
        }
      }
    }
    $$,
    variables := '{"emailAddress": "foo@bar.com"}'::jsonb
    );


    select graphql.resolve($$
    mutation newAccount($acc: AccountInsertInput) {
       createAccount(objects: [$acc]) {
        affectedCount
        results {
          id
          email
        }
      }
    }
    $$,
    variables := '{"acc": {"email": "bar@foo.com"}}'::jsonb
    );

    select graphql.resolve($$
    mutation newAccount($acc: [AccountInsertInput!]!) {
       createAccount(objects: $accs) {
        affectedCount
        results {
          id
          email
        }
      }
    }
    $$,
    variables := '{"accs": [{"email": "bar@foo.com"}]}'::jsonb
    );

    -- Should fail with field does not exist
    select graphql.resolve($$
    mutation createAccount($acc: AccountInsertInput) {
       createAccount(objects: [$acc]) {
        affectedCount
        results {
          id
          email
        }
      }
    }
    $$,
    variables := '{"acc": {"doesNotExist": "other"}}'::jsonb
    );

rollback;
