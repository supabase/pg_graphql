begin;

    create table public.account_holder(id int);

    select gql.to_type_name('public.account_holder');

    set search_path = '';

    select gql.to_type_name('public.account_holder');

    create table public."5ac!C h&"(id int);

    select gql.to_type_name('public."5ac!C h&"');

rollback;
