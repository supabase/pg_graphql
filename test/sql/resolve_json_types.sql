begin;

    create table exotic(
        id bigint primary key,
        js json not null,
        jsb jsonb not null
    );

    insert into exotic(id, js, jsb)
    values (1, '{"hello": 1}', '["world", "other"]');

    select jsonb_pretty(
        graphql.resolve($$
            {
              exoticCollection {
                edges {
                  node {
                    id
                    js
                    jsb
                  }
                }
              }
            }
        $$)
    );

rollback;
