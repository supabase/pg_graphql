begin;

    create table account(
        id serial primary key,
        email varchar(255) not null unique,
        to_change int not null
    );

    insert into public.account(email, to_change)
    values
        ('aardvark@x.com', 1);


    select graphql.resolve($$
    mutation {
      upsertAccount(
        object: {
            email: "aardvark@x.com"
            toChange: 2
        },
        onConflict: {
            conflictFields: ["id"]
            updateFields: ["toChange"]
        }
      ) {
        email
        toChange
      }
    }
    $$);

rollback;
