{ pkgs }:
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "cramfs-xip";
  version = "2.1";

  src = pkgs.fetchurl {
    url = "https://github.com/npitre/cramfs-tools/archive/refs/tags/v${finalAttrs.version}.tar.gz";
    hash = "sha256-zbek7K0DTwY7ZFazfN9lOuMXWKIkwyFh5UcSqdfwHMM=";
  };

  buildInputs = [ pkgs.zlib ];

  makeFlags = [ "CC=${pkgs.stdenv.cc.targetPrefix}cc" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin mkcramfs cramfsck
    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Tools for creating and checking CramFS file systems with XIP support";
    homepage = "https://github.com/npitre/cramfs-tools";
    license = licenses.gpl2Plus;
    platforms = platforms.unix;
    mainProgram = "mkcramfs";
  };
})
