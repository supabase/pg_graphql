begin;

    create table account(
        id serial primary key,
        encrypted_password varchar(255) not null
    );

    insert into public.account(encrypted_password)
    values
        ('hidden_hash');

    -- Superuser
    select gql.resolve(
        $$
        {
          allAccounts(first: 1) {
            edges {
              node {
                id
                encryptedPassword
              }
            }
          }
        }
        $$
    );


    create role api;
    -- Grant access to GQL
    grant usage on schema gql to api;
    grant all on all tables in schema gql to api;

    -- Allow access to public.account.id but nothing else
    grant usage on schema public to api;
    grant all on all tables in schema public to api;
    revoke select on public.account from api;
    grant select (id) on public.account to api;

    set role api;

    -- Select permitted columns
    select gql.resolve(
        $$
        {
          allAccounts(first: 1) {
            edges {
              node {
                id
              }
            }
          }
        }
        $$
    );

    -- Attempt select on revoked column
    select gql.resolve(
        $$
        {
          allAccounts(first: 1) {
            edges {
              node {
                id
                encryptedPassword
              }
            }
          }
        }
        $$
    );
rollback;
