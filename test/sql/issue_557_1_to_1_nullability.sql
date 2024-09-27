begin;

    -- Create the party table
    create table party (
        id uuid primary key default gen_random_uuid(),
        kind varchar not null -- Indicates whether the party is a 'contact' or an 'organisation'
    );

    -- Create the contact table
    create table contact (
        id uuid primary key, -- Also a foreign key to party.id
        given_name text,
        family_name text,
        foreign key (id) references party(id)
    );

    -- Create the organisation table
    create table organization (
        id uuid primary key, -- Also a foreign key to party.id
        name text not null,
        foreign key (id) references party(id)
    );

    -- Party should have nullable relationships to Contact and Organization
    select jsonb_pretty(
      graphql.resolve($$
        {
          __type(name: "Party") {
            kind
            fields {
              name
              type {
                name
                kind
                description
                ofType {
                  name
                  kind
                  description
                }

              }
            }
          }
        }
        $$)
    );

    -- Contact and Organization should have non-nullable relationship to Party
    select jsonb_pretty(
      graphql.resolve($$
        {
          __type(name: "Organization") {
            kind
            fields {
              name
              description
              type {
                name
                kind
                description
                ofType {
                  name
                  kind
                  description
                }
              }
            }
          }
        }
        $$)
    );

    select jsonb_pretty(
      graphql.resolve($$
        {
          __type(name: "Contact") {
            kind
            fields {
              name
              description
              type {
                name
                kind
                description
                ofType {
                  name
                  kind
                  description
                }
              }
            }
          }
        }
        $$)
    );

rollback;
