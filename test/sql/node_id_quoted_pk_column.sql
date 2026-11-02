begin;
    -- Regression test: NodeIdBuilder::to_sql (src/transpile.rs) interpolated
    -- primary key column names into the generated SQL without quote_ident, so
    -- any primary key column name that needs quoting broke nodeId selection,
    -- and a name carrying a SQL fragment was executed as SQL. The sibling
    -- NodeIdInstance::to_sql path (nodeId lookups and filters) was already
    -- quoted.

    -- Primary key column name carrying a SQL fragment that references a real
    -- column, as an attacker would write it. The column is not a
    -- valid GraphQL name so it is hidden from the schema, but nodeId still
    -- includes it.
    create table account(
        "email, (select 1/0)" int primary key,
        email text
    );
    insert into account values (1, 'a@x.com');

    -- Before the fix this failed with "division by zero"
    select jsonb_pretty(
        graphql.resolve($${accountCollection { edges { node { email nodeId } } }}$$)
    );

    -- Looking the record up by the nodeId returned above goes through
    -- NodeIdInstance::to_sql; both paths must agree
    select jsonb_pretty(
        graphql.resolve($$
            {
              node(nodeId: "WyJwdWJsaWMiLCAiYWNjb3VudCIsIDFd") {
                nodeId
                ... on Account {
                  email
                }
              }
            }
        $$)
    );

    -- Mixed case primary key column name. Before the fix this failed with
    -- "column blogid does not exist" because the unquoted name was folded to
    -- lower case.
    create table blog(
        "blogId" int primary key,
        title text
    );
    insert into blog values (7, 'hello');

    select jsonb_pretty(
        graphql.resolve($${blogCollection { edges { node { blogId title nodeId } } }}$$)
    );
rollback;
