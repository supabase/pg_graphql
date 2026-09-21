begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';

    create table account(
        id serial primary key
    );

    create table blog(
        id serial primary key,
        owner_id integer not null references account(id)
    );

    comment on constraint blog_owner_id_fkey
    on blog
    is E'@graphql({"foreign_name": "author", "local_name": "blogz"})';


    -- expect: 'author'
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Blog") {
            fields {
              name
            }
          }
        }
        $$)
    );

    -- expect: 'blogz'
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            fields {
              name
            }
          }
        }
        $$)
    );


rollback;
