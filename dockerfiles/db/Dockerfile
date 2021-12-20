FROM postgres:13 as build

RUN apt-get update
RUN apt-get install build-essential git cmake curl -y
RUN apt-get install postgresql-server-dev-13 -y
RUN apt-get install python2 -y

RUN git clone https://github.com/graphql/libgraphqlparser.git \
    && cd libgraphqlparser \
    && cmake . \
    && make install

COPY . pg_graphql
WORKDIR pg_graphql
RUN make install

FROM postgres:13 as main

ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"

COPY --from=build ["/usr/local/include/graphqlparser", "/usr/local/include/graphqlparser"]
COPY --from=build ["/usr/local/lib/libgraphqlparser.so", "/usr/local/lib/libgraphqlparser.so"]
COPY --from=build ["/usr/lib/postgresql", "/usr/lib/postgresql"]
COPY --from=build ["/usr/share/postgresql", "/usr/share/postgresql"]
COPY --from=build ["/pg_graphql/pg_graphql.control", "/usr/share/postgresql/13/extension/pg_graphql.control"]
