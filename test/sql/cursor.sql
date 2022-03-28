begin;
    -- Check SQL output
    select graphql.to_cursor_clause(
        'abc',
        array[('email', 'asc', true), ('id', 'asc', false)]::graphql.column_order_w_type[]
    );


    -- Check encode/decode round trip
    with c(ursor) as (
        select
            '("{""(email,asc,t)"",""(id,asc,f)""}","[""aardvark@x.com"", 1]")'::graphql.cursor
    )
    select
        c.ursor =
        graphql.decode(
            graphql.encode(
                c.ursor::graphql.cursor
            )
        )
    from c;

rollback
