begin;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    select graphql.resolve($$
    mutation createAccount($emailAddress: String) {
       xyz: upsertAccount(object: {
        email: $emailAddress
      }) {
        id
      }
    }
    $$,
    variables := '{"emailAddress": "foo@bar.com"}'::jsonb
    );


    select graphql.resolve($$
    mutation createAccount($acc: AccountInsertInput) {
       upsertAccount(object: $acc) {
        id
      }
    }
    $$,
    variables := '{"acc": {"email": "bar@foo.com"}}'::jsonb
    );


rollback;
