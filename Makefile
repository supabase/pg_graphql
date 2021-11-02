EXTENSION = pg_graphql
DATA = $(wildcard sql/*--*.sql)

PG_CONFIG = pg_config
SHLIB_LINK = -lgraphqlparser

MODULE_big = pg_graphql
OBJS = src/lib.o

TESTS = $(wildcard test/sql/*.sql)
REGRESS = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --use-existing --inputdir=test

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
