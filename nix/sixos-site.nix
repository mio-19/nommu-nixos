# Evaluate the upstream site -> host -> mkConfiguration fixpoint for the board.
# stack is a store snapshot produced by the pinned Xtensa SDK build. Nix builds
# the configuration and service database; no build-host ELF enters the image.
{
  nixpkgs,
  sixos-src,
  linux-src,
  stack,
  system,
}:
let
  pkgs = import nixpkgs { inherit system; };
  lib = pkgs.lib;
  # nixpkgs does not know Xtensa yet. Extend only sixos' platform inspection;
  # executable builds still use the actual ESP32-S3 SDK, never another CPU.
  targetLib = lib // {
    systems = lib.systems // {
      parse = lib.systems.parse // {
        mkSystemFromString =
          triple:
          if triple == "xtensa-esp32s3-linux-uclibcfdpic" then
            {
              _type = "system";
              cpu = {
                name = "xtensa";
                family = "xtensa";
                bits = 32;
                significantByte = lib.systems.parse.significantBytes.littleEndian;
              };
              vendor.name = "espressif";
              kernel = lib.systems.parse.kernels.linux;
              abi.name = "uclibcfdpic";
            }
          else
            lib.systems.parse.mkSystemFromString triple;
      };
    };
  };
  profile = "/nix/var/nix/profiles/system";
  runtime = pkgs.runCommand "esp32s3-skarnet-runtime" { } ''
      mkdir -p $out/bin $out/lib $out/libexec
      # Firmware runtime only: compilers, repository tools and unused s6 clients
      # stay on the build host so the closure fits the 7.5 MiB XIP partition.
      runtime_bins=(
    execlineb background case cd define dollarat elgetopt elgetpositionals elglob eltest
    emptyenv envfile exec execline-cd execline-umask exit export export-array fdblock
    fdclose fdmove fdreserve fdswap forbacktickx forstdin forx foreground getcwd getpid
    heredoc homeof if ifelse ifte ifthenelse importas loopwhilex multidefine multisubstitute
    pipeline piperw posix-cd posix-umask redirfd runblock shift trap tryexec umask
    unexport wait withstdinas
    s6-applyuidgid s6-fdholder-daemon s6-fdholder-retrieve s6-fdholderd
    s6-ipcclient s6-ipcserver s6-ipcserver-access s6-ipcserver-socketbinder s6-ipcserverd
    s6-linux-init s6-linux-init-echo s6-linux-init-hpr s6-linux-init-logouthookd
    s6-linux-init-nuke s6-linux-init-shutdown s6-linux-init-shutdownd
    s6-linux-init-telinit s6-linux-init-umountall
    s6-log s6-rc s6-rc-init s6-rc-update s6-setuidgid s6-softlimit s6-sudo s6-sudoc s6-sudod
    s6-supervise s6-svc s6-svlisten s6-svlisten1 s6-svscan s6-svscanctl s6-svwait s6-echo s6-envuidgid
      )
      for binary in "''${runtime_bins[@]}"; do
        cp ${stack}/target${profile}/bin/$binary $out/bin/
      done
      for binary in s6-ftrigrd s6-rc-fdholder-filler s6-rc-oneshot-run; do
        cp ${stack}/target${profile}/libexec/$binary $out/libexec/
      done
      cp ${stack}/target${profile}/lib/libfork.so.0 $out/lib/
      chmod u+w $out/bin
      mv $out/bin/s6-svscan $out/bin/s6-svscan.real
      install -m 755 ${../firmware/svscan} $out/bin/s6-svscan
  '';
  # Use a native Nix compiler linked against native libraries, but read the
  # target configuration headers when embedding paths in generated services.
  # This is the same mechanism nixpkgs uses for pkgsBuildTarget.s6-rc.
  compiler = pkgs.s6-rc.overrideAttrs (old: {
    postConfigure = (old.postConfigure or "") + ''
      substituteInPlace src/s6-rc/s6-rc-compile.c \
        --replace-fail '<execline/config.h>' '"${stack}/target${profile}/include/execline/config.h"' \
        --replace-fail '<s6/config.h>' '"${stack}/target${profile}/include/s6/config.h"' \
        --replace-fail '<s6-rc/config.h>' '"${stack}/target${profile}/include/s6-rc/config.h"'
    '';
  });
  base =
    pkgs.runCommand "esp32s3-base-runtime"
      {
        nativeBuildInputs = [ (import ./xip-cramfs.nix { inherit pkgs; }) ];
      }
      ''
        cramfsck -x root ${linux-src}/images/rootfs.cramfs
        mkdir -p $out
        cp -a root/{bin,sbin,usr,lib} $out/
        chmod -R u+w $out
        ln -s ../usr/bin/env $out/bin/env
        ln -s busybox $out/bin/reboot
        ln -s ../usr/sbin/nologin $out/bin/nologin
        for program in micropython socat make nano curl mmu-run fork-test \
          fork-test-dynamic process-test jobq programbench atfork-test; do
          rm -f $out/usr/bin/$program
        done
        rm -f $out/usr/lib/libcurl.so*
      '';
  init = import ./sixos-init.nix { inherit pkgs sixos-src; };
  # Builders execute on the host; runtime dependencies are Xtensa packages.
  # Tools unsupported by this flash appliance are never shipped (see below).
  targetPkgs = pkgs // {
    runtimeShell = "/usr/bin/dash";
    hostPlatform = {
      config = "xtensa-esp32s3-linux-uclibcfdpic";
    };
    busybox = base;
    util-linux = base;
    coreutils = base;
    cpio = base;
    e2fsprogs = base;
    pkgsStatic.busybox = base;
    s6 = runtime;
    s6-rc = runtime;
    execline = runtime;
    s6-portable-utils = runtime;
    doas = runtime;
    nix = runtime;
    kexec-tools = runtime;
    pkgsBuildTarget.s6-rc = compiler;
    callPackage =
      path: args:
      if baseNameOf (toString path) == "s6-linux-init.nix" then
        lib.makeOverridable (
          _:
          pkgs.runCommand "esp32s3-sixos-boot" { } ''
            mkdir -p $out/boot
            ln -s ${init}/init $out/boot/init
          ''
        ) args
      else
        lib.callPackageWith targetPkgs path args;
  };
  upstreamSite = import ./sixos-upstream.nix {
    inherit nixpkgs sixos-src;
    lib = targetLib;
    site-dir = {
      globals = { };
      subnets = { };
      # Upstream's tag application expects a platform overlay to return the
      # complete host, even when no generic architecture tag matches.
      tags.is-esp32s3.overlays = [ (_: prev: prev) ];
      overlay = [ ];
      hosts.reterminal-e1002 = final: prev: {
        canonical = "xtensa-esp32s3-linux-uclibcfdpic";
        pkgs = targetPkgs;
        sw = base;
        tags = prev.tags // {
          is-esp32s3 = true;
          has-initrd = false;
          has-initrd-abduco = false;
          has-initrd-lvm = false;
          has-initrd-mount-root = false;
          has-initrd-switch-root = false;
        };
        boot = prev.boot // {
          kernel = prev.boot.kernel // {
            package = base;
            payload = "${linux-src}/images/xipImage";
            image = "${linux-src}/images/xipImage";
            modules = null;
            firmware = null;
            console = {
              device = "ttyS0";
              baud = 115200;
            };
          };
          # No initrd is loaded by the ESP32 bootloader. Upstream also emits
          # a kexec helper; supply an empty archive before removing that helper.
          initrd.image = pkgs.writeText "no-esp32-initrd" "";
        };
        users.root = {
          shell = "/usr/bin/user-shell";
          home-directory = "/home/root";
          # Keep the persistent shadow hash and upstream first-login flow.
          hashed-password = "x";
        };
        extra-configuration-links."etc/hostname" = pkgs.writeText "hostname" "reterminal-e1002\n";
        # The board has no validated RTC. Save the clock at service shutdown
        # instead of running an additional periodic process on 8 MiB PSRAM.
        services = prev.services // {
          hwclock-fake =
            _:
            final.six.mkOneshot {
              up = "/usr/bin/dash ${./../firmware/clock-restore}";
              passthru = {
                before = [ final.targets.global.hwclock ];
                after = [ final.targets.early-setup ];
              };
            };
          hwclock-fake-updater =
            _:
            final.six.mkOneshot {
              up = "/bin/true";
              down = "/usr/bin/dash ${./../firmware/clock-save}";
              passthru.after = [
                final.targets.early-setup
                final.targets.global.hwclock
              ];
            };
        };
        targets = {
          default = final.six.mkBundle { };
          global.hwclock = final.six.mkBundle { };
          early-setup = final.six.mkOneshot {
            up = "/usr/bin/dash ${./../firmware/early-setup}";
          };
          console = final.six.mkService {
            type = "longrun";
            up = builtins.readFile ../firmware/console-run;
            # Interactive login shells ignore SIGTERM. Hang up the session
            # on shutdown, with a finite kill timeout for a stuck client.
            extraCommands = ''
              cp $out/up $out/run
              echo HUP > $out/down-signal
              echo 5000 > $out/timeout-kill
            '';
            passthru = {
              logger = false;
              after = [ final.targets.early-setup ];
            };
          };
        };
      };
    };
  };
  upstreamHost = upstreamSite.hosts.reterminal-e1002;
  # Firmware-specific deployment: immutable cramfs is replaced by the host
  # flasher, not nix-env or kexec on a target with 8 MiB of RAM. Keep upstream's
  # configuration, identity files, target scripts and compiled service graph.
  configuration = upstreamHost.configuration.overrideAttrs (old: {
    buildCommand =
      lib.replaceStrings [ "cp ${runtime}/bin/doas $out/bin/doas.unwrapped" ] [ "" ] old.buildCommand
      + ''
        rm $out/bin/{activate,deploy,dry-activate,kexec,kexec-load,nextboot}
        # The kernel is already in its XIP flash partition; including its source
        # store object would pull the entire upstream checkout into cramfs.
        rm $out/boot/{kernel,kernel-params,initrd,modprobe-wrapped}
        rm -f $out/etc/doas.conf
        rm -f $out/etc/services $out/etc/protocols
        cp ${../firmware/activate} $out/bin/activate
        chmod +x $out/bin/activate
        ln -s ${runtime}/lib $out/lib
        ln -s ${runtime}/libexec $out/libexec
        for binary in ${runtime}/bin/*; do
          ln -s "$binary" "$out/bin/$(basename "$binary")"
        done
        cp ${init}/s6-linux-init.cpio $out/boot/s6-linux-init.cpio
        cp ${init}/COPYING.sixos $out/COPYING.sixos
        echo '${
          builtins.toJSON {
            target = "reterminal-e1002";
            inherit (host) canonical;
            sixosRevision = sixos-src.rev or "unknown";
            deployment = "host-flashed immutable cramfs";
            targets = builtins.attrNames host.targets;
          }
        }' > $out/port-status.json
      '';
  });
  # Expose the platform-adapted configuration at the normal site/host paths.
  host = upstreamHost // {
    inherit configuration;
    inherit site;
  };
  site = upstreamSite // {
    hosts = upstreamSite.hosts // {
      reterminal-e1002 = host;
    };
  };
in
{
  inherit
    site
    host
    configuration
    runtime
    base
    init
    ;
}
