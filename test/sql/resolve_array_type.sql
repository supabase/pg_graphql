begin;

    create table exotic(
        id bigint primary key,
        tags text[] not null
    );

    insert into exotic(id, tags)
    values (1, array['a', 'b']);

    select jsonb_pretty(
        graphql.resolve($$
            {
              exoticCollection {
                edges {
                  node {
                    id
                    tags
                  }
                }
              }
            }
        $$)
    );

rollback;
