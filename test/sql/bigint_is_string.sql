begin;

    create table account(
        id bigserial primary key,
        parent_id int references account(id)
    );

    insert into account(id, parent_id)
    values (1,1);

    select graphql.resolve($$
    {
      accountCollection {
        edges {
          cursor
          node {
            id
            parent {
              id
            }
          }
        }
      }
    }
    $$);

rollback;
