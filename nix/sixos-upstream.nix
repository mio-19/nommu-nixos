# Pin the self-contained evaluation dependencies used by this sixos revision.
# Bundled vendor files avoid runtime network fetches and ensure hermetic evaluation.
{
  nixpkgs,
  sixos-src,
  site-dir,
  lib ? nixpkgs.lib,
}:
let
  infuse = (import ./vendor/infuse.nix { inherit lib; }).v1.infuse;
  readTree = import ./vendor/readTree.nix { };
  yants = import ./vendor/yants.nix;
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
