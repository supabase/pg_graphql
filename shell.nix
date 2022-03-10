let
  nixpkgs = builtins.fetchTarball {
    name = "2021-12";
    url = "https://github.com/NixOS/nixpkgs/archive/5f8babdd259d68ff8052dfc8d650ebdf9cc3bd75.tar.gz";
  };
in with import nixpkgs {};
mkShell {
  buildInputs =
    let
      libgraphqlparser = callPackage ./nix/libgraphqlparser {};

      pgWithExt = { pg }: pg.withPackages (p: [ (callPackage ./nix/pg_graphql { postgresql = pg; libgraphqlparser = libgraphqlparser; }) ]);
      pg14WithExt = pgWithExt { pg = postgresql_14; };
      pg_w_pg_graphql = callPackage ./nix/pg_graphql/pgScript.nix { postgresql = pg14WithExt; };
    in
    [ pg_w_pg_graphql ];
}
