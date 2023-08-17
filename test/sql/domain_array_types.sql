begin;

create schema other;

comment on schema public is e'@graphql({"inflect_names": true, "resolve_base_type": true})';

create domain int_array as int[];

create domain domain_int as int;

create domain domain_int_array as domain_int[];

create table domain_test (
  id serial primary key,
  field_int_array int_array,
  field_domain_int_array domain_int_array
);

select jsonb_pretty(
    graphql.resolve(
    $$
    {
      __type(name: "DomainTest") {
        fields {
          name
          type {
            kind
            ofType {
              kind
              name
              ofType {
                kind
                name
              }
            }
          }
        }
      }
    }
    $$
  )
);

rollback;