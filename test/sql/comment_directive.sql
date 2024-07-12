select
    graphql.comment_directive(
        comment_ := '@graphql({"name": "myField"})'
    );

select
    graphql.comment_directive(
        comment_ := '@graphql({"name": "myField with (parentheses)"})'
    );

select
    graphql.comment_directive(
        comment_ := '@graphql({"name": "myField with a (starting parenthesis"})'
    );

select
    graphql.comment_directive(
        comment_ := '@graphql({"name": "myField with an ending parenthesis)"})'
    );
