begin;

    create table public.account(
        id serial primary key,
        first_name varchar(255) not null,
        last_name varchar(255) not null
    );

    -- Extend with function
    create function public._full_name(rec public.account)
        returns text
        immutable
        strict
        language sql
    as $$
        select format('%s %s', rec.first_name, rec.last_name)
    $$;

    insert into public.account(first_name, last_name)
    values
        ('Foo', 'Fooington'),
        ('Bar', 'Barsworth');


    savepoint a;

    select jsonb_pretty(
        graphql.resolve($$
    {
      accountCollection {
        edges {
          node {
            id
            firstName
            lastName
            fullName
          }
        }
      }
    }
        $$)
    );

    rollback to savepoint a;

    select graphql.resolve($$
    {
      account(id: "WyJhY2NvdW50IiwgMV0=") {
        id
        fullName
      }
    }
    $$);

    rollback to savepoint a;

rollback;
