create or replace function graphql._first_agg(anyelement, anyelement)
    returns anyelement
    immutable
    strict
    language sql
as $$ select $1; $$;

create aggregate graphql.first(anyelement) (
    sfunc    = graphql._first_agg,
    stype    = anyelement,
    parallel = safe
);
