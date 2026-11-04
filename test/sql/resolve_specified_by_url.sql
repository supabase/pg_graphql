begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';

    -- specifiedByURL should be queryable and return null for built-in scalars
    select graphql.resolve(
        query:='{ __type(name: "Boolean") { specifiedByURL } }'
    );

    -- specifiedByURL should also work alongside other fields
    select graphql.resolve(
        query:='{ __type(name: "String") { name kind specifiedByURL } }'
    );

    -- specifiedByURL on a non-scalar type (e.g. OBJECT) should also return null
    select graphql.resolve(
        query:='{ __type(name: "Query") { name kind specifiedByURL } }'
    );

rollback;
