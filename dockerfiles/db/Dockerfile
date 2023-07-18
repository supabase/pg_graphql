FROM postgres:15
RUN apt-get update

ENV build_deps ca-certificates \
  git \
  build-essential \
  libpq-dev \
  postgresql-server-dev-15 \
  curl \
  libreadline6-dev \
  zlib1g-dev


RUN apt-get install -y --no-install-recommends $build_deps pkg-config cmake

WORKDIR /home/pg_graphql

ENV HOME=/home/pg_graphql \
  PATH=/home/pg_graphql/.cargo/bin:$PATH
RUN chown postgres:postgres /home/pg_graphql
USER postgres

RUN \
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --default-toolchain nightly && \
  rustup --version && \
  rustc --version && \
  cargo --version

# PGRX
RUN cargo install cargo-pgrx --version 0.9.7 --locked

RUN cargo pgrx init --pg15 $(which pg_config)

USER root

COPY . .
RUN cargo pgrx install

USER postgres
