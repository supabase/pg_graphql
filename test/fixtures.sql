create extension pg_graphql cascade;

comment on schema public is '@graphql({"inflect_names": true})';
