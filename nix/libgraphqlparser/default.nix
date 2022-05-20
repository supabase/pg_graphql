{ stdenv, fetchFromGitHub, cmake, python2 }:

stdenv.mkDerivation {
  name = "libgraphqlparser";
  builder = ./builder.sh;
  src = fetchFromGitHub {
    owner = "graphql";
    repo = "libgraphqlparser";
    rev = "7e6c35c7b9e919d0c40b28020fb9358c3cf2679c";
    sha256 = "sha256-4syYEE80HA7YuSjgRnK5KqF6yUSPHqDmbHnGEiLW98g=";
  };
  buildInputs = [ python2 ];
  inherit cmake;
}
