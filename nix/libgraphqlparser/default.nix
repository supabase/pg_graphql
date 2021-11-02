{ stdenv, fetchurl, cmake, python2 }:

stdenv.mkDerivation {
  name = "libgraphqlparser-0.7.0";
  builder = ./builder.sh;
  src = fetchurl {
    url = "https://github.com/graphql/libgraphqlparser/archive/refs/tags/0.7.0.tar.gz";
    sha256 = "63dae018f970dc2bdce431cbafbfa0bd3e6b10bba078bb997a3c1a40894aa35c";
  };
  inherit cmake; inherit python2;
}

