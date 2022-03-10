{ stdenv, postgresql, libgraphqlparser }:

stdenv.mkDerivation {
  name = "pg_graphql";

  buildInputs = [ postgresql libgraphqlparser ];

  src = ../../.;

  installPhase = ''
    ./bin/pgc build
    mkdir -p $out/bin
    install -D *.so -t $out/lib
    install -D -t $out/share/postgresql/extension *.sql
    install -D -t $out/share/postgresql/extension *.control
  '';
}
