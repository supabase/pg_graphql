begin;

create schema other;

-- Resolve base types respects the schema from where the table is defined not where the types are defined
-- Expect the base type for all fields not to resolve in this case even though one of the domains belong to a schema with resolve_base_type set to true
comment on schema public is e'@graphql({"inflect_names": true, "resolve_base_type": false})';
comment on schema other is e'@graphql({"inflect_names": true, "resolve_base_type": true})';

create domain domain_int AS int;
create domain other.domain_int AS int;


create table domain_test (
    id serial primary key,
    field_int domain_int,
    field_other_int other.domain_int
);

insert into domain_test(field_int, field_other_int)
values (1, 2);

savepoint a;

-- Check the old behavior resolves to opaque
select jsonb_pretty(
  graphql.resolve (
    $$
      {
        __type(name: "DomainTest") {
          kind
          fields {
              name
              type {
                  name
                  kind
              }
          }
        }
      }
    $$
  )
);

select jsonb_pretty(
  graphql.resolve(
    $$
    {
      __type(name: "DomainTestFilter"){
        inputFields{
          name
          type{
            name
          }
        }
      }
    }
    $$
  )
);

rollback to a;

-- Expect the new behavior to resolve to the base type
comment on schema public is e'@graphql({"inflect_names": true, "resolve_base_type": true})';
comment on schema other is e'@graphql({"inflect_names": true, "resolve_base_type": false})';

select jsonb_pretty(
  graphql.resolve (
    $$
      {
        __type(name: "DomainTest") {
          kind
          fields {
              name
              type {
                  name
                  kind
              }
          }
        }
      }
    $$
  )
);

select jsonb_pretty(
  graphql.resolve(
    $$
    {
      __type(name: "DomainTestFilter"){
        inputFields{
          name
          type{
            name
          }
        }
      }
    }
    $$
  )
);


rollback;
