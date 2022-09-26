begin;

    create table project(
        id serial primary key,
        name varchar(255) not null
    );

    select graphql.resolve($$
    mutation {
      insertIntoProjectCollection(objects: [
        { name: "aaaa%aaaa"},
      ]) {
        affectedCount
        records {
          id
          name
        }
      }
    }
    $$);

rollback;
