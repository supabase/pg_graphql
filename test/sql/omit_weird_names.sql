begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';

    savepoint a;

    create table "@xyz"( id int primary key);

    select jsonb_pretty(
        graphql.resolve($$
            {
              __schema {
                types {
                  name
                }
              }
            }
        $$)
    );

    rollback to savepoint a;

    create table xyz( "! q" int primary key);
    select jsonb_pretty(
        graphql.resolve($$
            {
              __type(name: "Xyz") {
                fields {
                  name
                }
              }
            }
        $$)
    );

    rollback to savepoint a;

rollback;
