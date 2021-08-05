FROM postgres:13

RUN apt-get update
RUN apt-get install build-essential git cmake curl -y
RUN apt-get install postgresql-server-dev-13 -y
# Required by libgraphql
RUN apt-get install python2 -y
RUN curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
RUN python2 get-pip.py
RUN pip install ctypesgen

RUN git clone https://github.com/graphql/libgraphqlparser.git \
    && cd libgraphqlparser \
    && cmake . \
    && make install

ENV LD_LIBRARY_PATH="/usr/local/lib:${PATH}"
#ENV PATH="/usr/local/lib:${PATH}"

COPY . pg_graphql
WORKDIR pg_graphql
RUN make install
