begin;

    create table "AccountHolder"(
        "someId" int primary key,
        "accountHolderId" int references "AccountHolder"("someId")
    );

    insert into public."AccountHolder"("someId", "accountHolderId")
    values
        (1, 1),
        (2, 2);

    -- Select
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountHolderCollection(first: 1) {
                pageInfo{
                  startCursor
                  endCursor
                  hasNextPage
                  hasPreviousPage
                }
                edges {
                  cursor
                  node {
                    someId
                    accountHolderId
                    accountHolder {
                      someId
                    }
                    accountHolderCollection {
                      totalCount
                    }
                  }
                }
              }
            }
        $$)
    );


    -- Paginate
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountHolderCollection(first: 1 after: "WyJcIlwiXCJBY2NvdW50SG9sZGVyXCJcIlwiIiwgMV0=" ) {
                edges {
                  cursor
                  node {
                    someId
                    accountHolderId
                    accountHolder {
                      someId
                    }
                    accountHolderCollection {
                      totalCount
                    }
                  }
                }
              }
            }
        $$)
    );

    -- Insert
    select graphql.resolve($$
    mutation {
      insertIntoAccountHolderCollection(objects: [{
        someId: 3
        accountHolderId: 2
      }]) {
        records {
          someId
          accountHolder {
            someId
          }
        }
      }
    }
    $$);

    -- Update
    select graphql.resolve($$
    mutation {
      updateAccountHolderCollection(
        set: {accountHolderId: 3}
        filter: {someId: {eq: 3}}
      ) {
        affectedCount
        records {
          someId
          accountHolder {
            someId
          }
        }
      }
    }
    $$);

    -- Delete
    select graphql.resolve($$
    mutation {
      deleteFromAccountHolderCollection(
        filter: {someId: {eq: 3}}
      ) {
        affectedCount
        records {
          someId
          accountHolder {
            someId
          }
        }
      }
    }
    $$);

rollback;
