# Evaluate sixos' actual stage-one builder with fixed target filesystem paths.
# Only the maker, fakeroot and cpio execute on the build host.
{ pkgs, sixos-src }:
let
  targetPath = {
    outPath = "/usr";
  };
  targetBusybox = {
    outPath = "";
  };
  generated = pkgs.callPackage "${sixos-src}/mkConfiguration/s6-linux-init.nix" {
    runtimeShell = "/bin/sh";
    pkgs = {
      pkgsStatic.busybox = targetBusybox;
      busybox = targetBusybox;
    };
    coreutils = targetBusybox;
    s6-rc = targetPath;
    pkgsBuildHost = pkgs;
    buildPackages = pkgs;
    default-timezone = "UTC0";
    initial-path = "/usr/bin:/usr/sbin:/bin:/sbin";
    # The upstream kernel mounts devtmpfs on /dev at boot
    # (CONFIG_DEVTMPFS_MOUNT); an additional mount in stage one fails EBUSY.
    devtmpfs-mountpoint = null;
  };
in
pkgs.runCommand "sixos-esp32s3-init-template"
  {
    nativeBuildInputs = [
      pkgs.cpio
      pkgs.python3
      pkgs.fakeroot
    ];
    postFixup = ''
      sed -i '1c#!/bin/sh' $out/init
      if grep -Fq '${generated}' $out/init; then
        echo 'Host build store reference remains in the target init wrapper' >&2
        exit 1
      fi
    '';
  }
  ''
    mkdir -p tree $out
    cd tree
    cat > $out/rc.init <<'RCINIT'
    #!/bin/bash
    set -eu
    exec /nix/var/nix/profiles/system/bin/activate
    RCINIT
    fakeroot bash ${../tools/package-sixos-init.sh} \
      . "$out/s6-linux-init.cpio" "$out/rc.init" \
      ${generated}/s6-linux-init.cpio ${../tools/relocate-init.py}
    cp ${generated}/boot/init $out/init
    chmod u+w $out/init
    sed -i '1c#!/bin/sh' $out/init
    # The upstream wrapper's archive lives in the fixed target root filesystem.
    substituteInPlace $out/init \
      --replace-fail '${generated}/s6-linux-init.cpio' '/nix/var/nix/profiles/system/boot/s6-linux-init.cpio'
    cp ${sixos-src}/COPYING.GPL3-ONLY $out/COPYING.sixos
  ''
