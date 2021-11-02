{ stdenv, postgresql, libgraphqlparser }:

stdenv.mkDerivation {
  name = "pg_graphql";

  buildInputs = [ postgresql libgraphqlparser ];

  src = ../../.;

  installPhase = ''
    mkdir -p $out/bin
    install -D pg_graphql.so -t $out/lib
    install -D -t $out/share/postgresql/extension sql/*.sql
    install -D -t $out/share/postgresql/extension pg_graphql.control
  '';
}
