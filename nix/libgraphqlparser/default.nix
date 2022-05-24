{ stdenv, fetchFromGitHub, cmake, python2 }:

stdenv.mkDerivation {
  name = "libgraphqlparser";
  builder = ./builder.sh;
  src = fetchFromGitHub {
    owner = "graphql";
    repo = "libgraphqlparser";
    rev = "3b64cd52d13621921990a5801ba019e8a9402599";
    sha256 = "sha256-0ubcB2GykZnId4CL+pb4U0Ry2JftqwaEUh2DqeghHo0=";
  };
  buildInputs = [ python2 ];
  inherit cmake;
}
