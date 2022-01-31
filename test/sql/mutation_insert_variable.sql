begin;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    select graphql.resolve($$
    mutation createAccount($emailAddress: String) {
       xyz: insertAccount(object: {
        email: $emailAddress
      }) {
        id
      }
    }
    $$,
    variables := '{"emailAddress": "foo@bar.com"}'::jsonb
    );

rollback;
