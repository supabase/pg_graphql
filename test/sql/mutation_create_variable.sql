begin;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    select graphql.resolve($$
    mutation newAccount($emailAddress: String) {
       xyz: createAccount(object: {
        email: $emailAddress
      }) {
        id
      }
    }
    $$,
    variables := '{"emailAddress": "foo@bar.com"}'::jsonb
    );


    select graphql.resolve($$
    mutation newAccount($acc: AccountInsertInput) {
       createAccount(object: $acc) {
        id
      }
    }
    $$,
    variables := '{"acc": {"email": "bar@foo.com"}}'::jsonb
    );

    -- Should fail with field does not exist
    select graphql.resolve($$
    mutation createAccount($acc: AccountInsertInput) {
       createAccount(object: $acc) {
        id
      }
    }
    $$,
    variables := '{"acc": {"doesNotExist": "other"}}'::jsonb
    );

rollback;
