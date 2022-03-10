begin;

    create table account(
        id serial primary key,
        email varchar(255) not null,
        encrypted_password varchar(255) not null,
        created_at timestamp not null,
        updated_at timestamp not null
    );
    comment on table account is e'@graphql({"totalCount": {"enabled": true}})';


    create table blog(
        id serial primary key,
        owner_id integer not null references account(id),
        name varchar(255) not null,
        description varchar(255),
        created_at timestamp not null,
        updated_at timestamp not null
    );


    create type blog_post_status as enum ('PENDING', 'RELEASED');


    create table blog_post(
        id uuid not null default gen_random_uuid() primary key,
        blog_id integer not null references blog(id),
        title varchar(255) not null,
        body varchar(10000),
        status blog_post_status not null,
        created_at timestamp not null,
        updated_at timestamp not null
    );


    select jsonb_pretty(
        graphql.resolve($$

    query IntrospectionQuery {
      __schema {
        queryType {
          name
        }
        mutationType {
          name
        }
        types {
          ...FullType
        }
        directives {
          name
          description
          locations
          args {
            ...InputValue
          }
        }
      }
    }

    fragment FullType on __Type {
      kind
      name
      description
      fields(includeDeprecated: true) {
        name
        description
        args {
          ...InputValue
        }
        type {
          ...TypeRef
        }
        isDeprecated
        deprecationReason
      }
      inputFields {
        ...InputValue
      }
      interfaces {
        ...TypeRef
      }
      enumValues(includeDeprecated: true) {
        name
        description
        isDeprecated
        deprecationReason
      }
      possibleTypes {
        ...TypeRef
      }
    }

    fragment InputValue on __InputValue {
      name
      description
      type {
        ...TypeRef
      }
      defaultValue
    }

    fragment TypeRef on __Type {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
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
      }
    }
        $$)
    );

rollback;
