create extension "uuid-ossp";
create extension pg_graphql;

create table account(
    id uuid not null default uuid_generate_v4() primary key,
    email varchar(255) not null,
    encrypted_password varchar(255) not null,
    created_at timestamp not null,
    updated_at timestamp not null
);


create table blog(
    id uuid not null default uuid_generate_v4() primary key,
    owner_id uuid not null references account(id),
    name varchar(255) not null,
    description varchar(255),
    created_at timestamp not null,
    updated_at timestamp not null
);


create type blog_post_status as enum ('PENDING', 'RELEASED');


create table blog_post(
    id uuid not null default uuid_generate_v4() primary key,
    blog_id uuid not null references blog(id),
    title varchar(255) not null,
    body varchar(10000),
    status blog_post_status not null,
    created_at timestamp not null,
    updated_at timestamp not null
);


-- 5 Accounts
insert into public.account(email, encrypted_password, created_at, updated_at)
values
    ('aardvark@x.com', 'asdfasdf', now(), now()),
    ('bat@x.com', 'asdfasdf', now(), now()),
    ('cat@x.com', 'asdfasdf', now(), now()),
    ('dog@x.com', 'asdfasdf', now(), now()),
    ('elephant@x.com', 'asdfasdf', now(), now());

insert into blog(owner_id, name, description, created_at, updated_at)
values
    ((select id from account where email ilike 'a%'), 'A: Blog 1', 'a desc1', now(), now()),
    ((select id from account where email ilike 'a%'), 'A: Blog 2', 'a desc2', now(), now()),
    ((select id from account where email ilike 'a%'), 'A: Blog 3', 'a desc3', now(), now()),
    ((select id from account where email ilike 'b%'), 'A: Blog 3', 'a desc1', now(), now());


-- Populate graphql schema
select gql.build_schema();
