begin;
    -- Superuser
    select gql.resolve($$
    {
      account(id: "WyJhY2NvdW50IiwgMV0=") {
        id
        encryptedPassword
      }
    }
    $$);

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
    select gql.resolve($$
    {
      account(id: "WyJhY2NvdW50IiwgMV0=") {
        id
      }
    }
    $$);

    -- Attempt select on revoked column
    select gql.resolve($$
    {
      account(id: "WyJhY2NvdW50IiwgMV0=") {
        id
        encryptedPassword
      }
    }
    $$);
rollback;
