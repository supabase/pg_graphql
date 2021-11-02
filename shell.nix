let
  nixpkgs = builtins.fetchTarball {
    name = "2020-12-22";
    url = "https://github.com/NixOS/nixpkgs/archive/2a058487cb7a50e7650f1657ee0151a19c59ec3b.tar.gz";
    sha256 = "1h8c0mk6jlxdmjqch6ckj30pax3hqh6kwjlvp2021x3z4pdzrn9p";
  };
in with import nixpkgs {};
mkShell {
  buildInputs =
    let
      libgraphqlparser = callPackage ./nix/libgraphqlparser {};

      pgWithExt = { pg }: pg.withPackages (p: [ (callPackage ./nix/pg_graphql { postgresql = pg; libgraphqlparser = libgraphqlparser; }) ]);
      pg13WithExt = pgWithExt { pg = postgresql_13; };
      pg_w_pg_graphql = callPackage ./nix/pg_graphql/pgScript.nix { postgresql = pg13WithExt; };
    in
    [ pg_w_pg_graphql nixops ];
}
