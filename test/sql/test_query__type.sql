begin;
    comment on schema public is e'@graphql({"inflect_names": true, "introspection": true})';
    select graphql.resolve(
        query:='query Abc { __type(name: "Int") { name kind description } }'
    );
rollback;
