-- Turn on automatic inflection of type names
comment on schema public is '@graphql({"inflect_names": true})';

create table account(
    id serial primary key,
    email varchar(255) not null,
    created_at timestamp not null,
    updated_at timestamp not null
);

-- enable a `totalCount` field on the `account` query type
comment on table account is e'@graphql({"totalCount": {"enabled": true}})';

create table blog(
    id serial primary key,
    owner_id integer not null references account(id),
    name varchar(255) not null,
    description varchar(255),
    tags text[],
    created_at timestamp not null,
    updated_at timestamp not null
);

create type blog_post_status as enum ('PENDING', 'RELEASED');

create table blog_post(
    id uuid not null default gen_random_uuid() primary key,
    blog_id integer not null references blog(id),
    title varchar(255) not null,
    body varchar(10000),
    status blog_post_status not null,
    created_at timestamp not null,
    updated_at timestamp not null
);
