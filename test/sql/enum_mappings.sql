begin;
create type my_enum as enum ('test', 'valid value');
comment on type my_enum is E'@graphql({"mappings": {"valid value": "valid_value"}})';
create table enums (
   id serial primary key,
   value my_enum
);
insert into enums (value) values ('test'), ('valid value');
select graphql.resolve($$
    {
      enumsCollection {
        edges {
            node {
             value
            }
        }
      }
    }
$$);
rollback;
