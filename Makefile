EXTENSION = pg_graphql
DATA = $(wildcard sql/*--*.sql)

#PG_LDFLAGS= -I/usr/local/lib/libgraphqlparser.so
PG_CONFIG = pg_config
SHLIB_LINK = -lgraphqlparser

MODULE_big = pg_graphql
OBJS = src/worker.o

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
