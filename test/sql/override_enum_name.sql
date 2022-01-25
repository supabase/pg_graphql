begin;
    create type account_priority as enum ('high', 'standard');
    comment on type public.account_priority is E'@graphql({"name": "CustomerValue"})';

    select name from graphql.type where enum = 'public.account_priority'::regtype;

rollback;
