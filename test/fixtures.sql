create extension pg_graphql cascade;
create extension "uuid-ossp";


comment on schema public is '@graphql({"inflect_names": true})';
