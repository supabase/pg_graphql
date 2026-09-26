begin;
    create table account(
        id int primary key,
        score int
    );

    insert into public.account(id, score)
    values
        (1, 10),
        (2, null),
        (3, 20),
        (4, null);

    -- AscNullsLast: order is 1, 3, 2, 4. The first page ends on id 3
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 2, orderBy: [{score: AscNullsLast}]) {
                pageInfo { hasNextPage endCursor }
                edges { node { id score } }
              }
            }
        $$)
    );

    -- AscNullsLast: after id 3 ([20, 3]) the null rows 2 and 4 follow
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 2, after: "WzIwLCAzXQ==", orderBy: [{score: AscNullsLast}]) {
                pageInfo { hasNextPage }
                edges { node { id score } }
              }
            }
        $$)
    );

    -- AscNullsLast: after id 1 ([10, 1]) the page holds id 3, and the null rows after it mean hasNextPage is true
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 1, after: "WzEwLCAxXQ==", orderBy: [{score: AscNullsLast}]) {
                pageInfo { hasNextPage }
                edges { node { id score } }
              }
            }
        $$)
    );

    -- DescNullsLast: order is 3, 1, 2, 4. After id 1 ([10, 1]) the null rows 2 and 4 follow
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 2, after: "WzEwLCAxXQ==", orderBy: [{score: DescNullsLast}]) {
                edges { node { id score } }
              }
            }
        $$)
    );

    -- AscNullsFirst: order is 2, 4, 1, 3. Before id 1 ([10, 1]) come the null rows 2 and 4
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(last: 2, before: "WzEwLCAxXQ==", orderBy: [{score: AscNullsFirst}]) {
                edges { node { id score } }
              }
            }
        $$)
    );

    -- AscNullsFirst: after id 2 ([null, 2]) come 4, then the non-null rows (already worked)
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(first: 3, after: "W251bGwsIDJd", orderBy: [{score: AscNullsFirst}]) {
                edges { node { id score } }
              }
            }
        $$)
    );

rollback;
