begin;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );


    insert into public.account(email)
    values
        ('aardvark@x.com');


    create table blog(
        id serial primary key,
        owner_id integer not null references account(id),
        name varchar(255) not null
    );


    insert into blog(owner_id, name)
    values
        ((select id from account where email ilike 'a%'), 'A: Blog 1'),
        ((select id from account where email ilike 'a%'), 'A: Blog 2'),
        ((select id from account where email ilike 'a%'), 'A: Blog 3'),
        ((select id from account where email ilike 'b%'), 'B: Blog 4');

    -- Connection: alias all field types and operation
    select jsonb_pretty(
        graphql.resolve($$
    {
      aA: allAccounts(first: 1) {
        tc: totalCount
        pi: pageInfo {
          hnp: hasNextPage
        }
        e: edges {
          c: cursor
          n: node{
            id_: id
            ni: nodeId
            b: blogs {
              tc2: totalCount
            }
          }
        }
      }
    }
        $$)
    );


    select graphql.resolve($$
    {
      acc: account(id: "WyJhY2NvdW50IiwgMV0=") {
        id_: id
        N: nodeId
      }
    }
    $$);


    select graphql.resolve($$
    query Introspec {
      s: __schema {
        q: queryType {
          n: name
        }
      }
    }
    $$);


rollback;
