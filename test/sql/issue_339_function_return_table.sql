begin;
    create table public.account(
        id int primary key
    );

    create function public._computed(rec public.account)
        returns table ( id int )
        immutable
        strict
        language sql
    as $$
        select 2 as id;
    $$;

    insert into account(id) values (1);

    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            kind
            fields {
                name
            }
          }
        }
        $$)
    );

    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection {
                edges {
                  node {
                    id
                    computed
                  }
                }
              }
            }
        $$)
    );

rollback;
