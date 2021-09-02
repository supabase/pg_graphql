create extension "uuid-ossp";

create table account(
	id uuid not null default uuid_generate_v4() primary key, 
	email varchar(255) not null,
	encrypted_password varchar(255) not null,
	created_at timestamp not null,
	updated_at timestamp not null
);
