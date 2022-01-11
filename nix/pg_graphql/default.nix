{ stdenv, postgresql, libgraphqlparser }:

stdenv.mkDerivation {
  name = "pg_graphql";

  buildInputs = [ postgresql libgraphqlparser ];

  src = ../../.;

  installPhase = ''
    ./bin/build.sh
    mkdir -p $out/bin
    install -D pg_graphql.so -t $out/lib
    install -D -t $out/share/postgresql/extension pg_graphql--0.1.0.sql
    install -D -t $out/share/postgresql/extension pg_graphql.control
  '';
}
