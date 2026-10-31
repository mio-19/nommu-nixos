# Pin the self-contained evaluation dependencies used by this sixos revision.
# Explicit fetches also avoid an unbounded depot Git checkout during evaluation.
{
  nixpkgs,
  sixos-src,
  site-dir,
  lib ? nixpkgs.lib,
}:
let
  infuse =
    (import (builtins.fetchurl {
      url = "https://codeberg.org/amjoseph/infuse.nix/raw/commit/fb79a7663a229c41400256359882261fc23f001a/default.nix";
      sha256 = "sha256-k+1GtiX/ZPsIxog6NoMSrjf7aO/3zZzrscllHVyIdtY=";
    }) { inherit lib; }).v1.infuse;
  readTree = import (builtins.fetchurl {
    url = "https://codeberg.org/amjoseph/depot/raw/commit/874181181145c7004be6164baea912bde78f43f6/nix/readTree/default.nix";
    sha256 = "1hfidfd92j2pkpznplnkx75ngw14kkb2la8kg763px03b4vz23zf";
  }) { };
  yants = import (
    builtins.fetchurl {
      url = "https://code.tvl.fyi/plain/nix/yants/default.nix";
      sha256 = "026j3a02gnynv2r95sm9cx0avwhpgcamryyw9rijkmc278lxix8j";
    }
  );
in
import sixos-src {
  nixpkgs-path = nixpkgs;
  inherit
    lib
    infuse
    readTree
    yants
    site-dir
    ;
  # The pinned upstream's host schema predates its boot.rootfs attrset and
  # does not export a site validator. Attribute-name checks still run.
  check-types = false;
}
