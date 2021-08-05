EXTENSION = pg_graphql
DATA = $(wildcard sql/*--*.sql)

PG_CONFIG = pg_config
SHLIB_LINK = -lgraphqlparser

MODULE_big = pg_graphql
OBJS = src/lib.o

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
