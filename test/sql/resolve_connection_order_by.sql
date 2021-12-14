begin;
    create table account(
        id int primary key,
        "spiritAnimal" text
    );

    insert into public.account(id, "spiritAnimal")
    values
        (1, 'bat'),
        (2, 'aardvark'),
        (3, 'aardvark');


    select jsonb_pretty(
        graphql.resolve($$
            {
              allAccounts(orderBy: [{id: DescNullsLast}]) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );


    select jsonb_pretty(
        graphql.resolve($$
            {
              allAccounts(orderBy: [{spiritAnimal: AscNullsLast}, {id: AscNullsLast}]) {
                edges {
                  node {
                    id
                    spiritAnimal
                  }
                }
              }
            }
        $$)
    );

rollback;
