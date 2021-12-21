FROM postgres:13 as build

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      cmake \
      git \
      postgresql-server-dev-13 \
      python2 \
    && rm -rf "/var/lib/apt/lists/*"

RUN export LIBGRAPHQLPARSER_VERSION="v0.7.0" \
    export LIBGRAPHQLPARSER_REPO="git@github.com:graphql/libgraphqlparser.git" \
    && git clone -b "${LIBGRAPHQLPARSER_VERSION}" --depth 1 "${LIBGRAPHQLPARSER_REPO}" \
    && cd libgraphqlparser \
    && cmake . \
    && make install

COPY . pg_graphql
WORKDIR /pg_graphql
RUN make install

FROM postgres:13 as main

# libgraphqlparser
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
COPY --from=build ["/usr/local/lib/libgraphqlparser.so", "/usr/local/lib/libgraphqlparser.so"]

# pg_graphql
COPY --from=build ["/usr/lib/postgresql/13/lib/bitcode/pg_graphql/", "/usr/lib/postgresql/13/lib/bitcode/pg_graphql/"]
COPY --from=build ["/usr/lib/postgresql/13/lib/bitcode/pg_graphql.index.bc", "/usr/lib/postgresql/13/lib/bitcode/pg_graphql.index.bc"]
COPY --from=build ["/usr/lib/postgresql/13/lib/pg_graphql.so", "/usr/lib/postgresql/13/lib/pg_graphql.so"]
COPY --from=build ["/usr/share/postgresql/13/extension/pg_graphql--0.1.sql", "/usr/share/postgresql/13/extension/pg_graphql--0.1.sql"]
COPY --from=build ["/usr/share/postgresql/13/extension/pg_graphql.control", "/usr/share/postgresql/13/extension/pg_graphql.control"]
