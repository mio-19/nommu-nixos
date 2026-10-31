{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "cramfs-xip";
  version = "2.1";
  src = pkgs.fetchurl {
    url = "https://github.com/npitre/cramfs-tools/archive/refs/tags/v2.1.tar.gz";
    hash = "sha256-zbek7K0DTwY7ZFazfN9lOuMXWKIkwyFh5UcSqdfwHMM=";
  };
  buildInputs = [ pkgs.zlib ];
  makeFlags = [ "CC=cc" ];
  installPhase = "mkdir -p $out/bin; cp mkcramfs cramfsck $out/bin/";
}
