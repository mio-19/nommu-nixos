{
  description = "reTerminal E1002 Xtensa/NOMMU firmware port workspace (sixos init)";
  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.zst";
    flake-utils.url = "github:numtide/flake-utils";
    linux-esp32-s3-src = {
      url = "github:paulneja/Linux-on-esp32-S3";
      flake = false;
    };
    sixos-src = {
      url = "git+https://codeberg.org/amjoseph/sixos.git";
      flake = false;
    };
  };
  outputs =
    inputs@{ nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        sources = {
          linux = inputs.linux-esp32-s3-src;
          sixos = inputs.sixos-src;
        };
        manifest = pkgs.writeText "port-status.json" (
          builtins.toJSON {
            target = "reterminal-e1002";
            cpu = "xtensa-esp32s3";
            mmu = false;
            requestedInit = "sixos";
            userspacePolicy = "Conventional C/C++; correctness assumed";
            firmwareReady = false;
            blockers = [
              "full sixos site/configuration evaluation for the Xtensa target"
              "E1002 board support and matched kernel/ESP-IDF flash layout"
              "Hardware boot, peripheral validation, and memory/resource measurements"
            ];
            revisions = builtins.mapAttrs (_: src: src.rev) sources;
          }
        );
        portingKit = pkgs.runCommand "reterminal-e1002-porting-kit" { } ''
          mkdir -p $out/sources $out/docs $out/board
          ln -s ${sources.linux} $out/sources/linux-esp32-s3
          ln -s ${sources.sixos} $out/sources/sixos
          cp ${manifest} $out/port-status.json
          cp ${./README.md} $out/README.md
          cp ${./docs/porting.md} $out/docs/porting.md
          cp ${./reterminal-e1002/partitions_32mb.csv} $out/board/partitions_32mb.PROPOSED.csv
        '';
        sixosInit = import ./nix/sixos-init.nix {
          inherit pkgs;
          sixos-src = sources.sixos;
        };
        sixosServices = import ./nix/sixos-services.nix {
          inherit pkgs;
          sixos-src = sources.sixos;
          early-setup = ./firmware/early-setup;
          console-run = ./firmware/console-run;
        };
        xipCramfs = pkgs.stdenv.mkDerivation {
          pname = "cramfs-xip";
          version = "2.1";
          src = pkgs.fetchurl {
            url = "https://github.com/npitre/cramfs-tools/archive/refs/tags/v2.1.tar.gz";
            hash = "sha256-zbek7K0DTwY7ZFazfN9lOuMXWKIkwyFh5UcSqdfwHMM=";
          };
          buildInputs = [ pkgs.zlib ];
          makeFlags = [ "CC=cc" ];
          installPhase = "mkdir -p $out/bin; cp mkcramfs cramfsck $out/bin/";
        };
        espEmuAssets = {
          x86_64-linux = {
            file = "esp-emu-0.51.0-x86_64-unknown-linux-gnu.tar.gz";
            hash = "sha256-K54VdHDtuLAxZ5llUCksbfjMZxYCXrrYkn25UNeTFBc=";
          };
          aarch64-linux = {
            file = "esp-emu-0.51.0-aarch64-unknown-linux-gnu.tar.gz";
            hash = "sha256-P8qFTfjR/C/HPjfzpOnbIUFm0OB9/b1HAgGf2dzDFG8=";
          };
          aarch64-darwin = {
            file = "esp-emu-0.51.0-aarch64-apple-darwin.tar.gz";
            hash = "sha256-qwJSS9KGzoRXdjlzHQ5I1iPOm+ZeRdnhJG3SIMFHYQI=";
          };
        };
        espEmu = pkgs.stdenvNoCC.mkDerivation {
          pname = "esp-emu";
          version = "0.51.0";
          src = pkgs.fetchurl {
            url = "https://github.com/espressif/esp-emulator/releases/download/v0.51.0/${espEmuAssets.${system}.file}";
            inherit (espEmuAssets.${system}) hash;
          };
          dontUnpack = true;
          nativeBuildInputs = [ pkgs.gnutar ];
          installPhase = ''
            mkdir -p $out/bin
            tar -xzf $src --strip-components=1 -C $out/bin
            chmod 755 $out/bin/esp-emu
          '';
        };
        skarnetSources =
          pkgs.runCommand "skarnet-pinned-sources"
            {
              nativeBuildInputs = [
                pkgs.gnutar
                pkgs.gzip
              ];
            }
            (
              "mkdir -p $out\n"
              +
                pkgs.lib.concatMapStringsSep "\n"
                  (name: ''
                    mkdir -p $out/${name}
                    tar xf ${pkgs.${name}.src} --strip-components=1 -C $out/${name}
                  '')
                  [
                    "skalibs"
                    "execline"
                    "s6"
                    "s6-rc"
                    "s6-linux-init"
                  ]
            );
        upstreamReference = pkgs.stdenvNoCC.mkDerivation {
          pname = "esp32s3-upstream-reference-NOT-E1002-sixos";
          version = sources.linux.shortRev;
          src = sources.linux;
          nativeBuildInputs = [
            pkgs.esptool
            pkgs.python3
          ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            python3 ${./tools/check-layout.py} \
              new-files/esp-hosted/network_adapter/partition_table.esp32s3.16m8r \
              --flash-bytes 16777216 --images images
            esptool --chip esp32s3 merge-bin \
              --flash-mode dio --flash-freq 80m --flash-size 16MB \
              --pad-to-size 16MB -o reference.bin \
              0x0 images/bootloader.bin 0x8000 images/partition-table.bin \
              0x10000 images/network_adapter.bin 0xd0000 images/etc.jffs2 \
              0x140000 images/xipImage 0x540000 images/rootfs.cramfs \
              0xcc0000 images/home.jffs2
            runHook postBuild
          '';
          installPhase = ''
            mkdir -p $out
            cp reference.bin $out/esp32s3-16mb-upstream-reference.bin
            cp ${manifest} $out/port-status.json
            echo 'Upstream prebuilt 16MB devkit reference only. No sixos. E1002 untested.' > $out/README
          '';
        };
      in
      {
        packages = {
          default = portingKit;
          porting-kit = portingKit;
          upstream-reference = upstreamReference;
          skarnet-sources = skarnetSources;
          cramfs-xip = xipCramfs;
          sixos-init = sixosInit;
          sixos-service-source = sixosServices;
          esp-emu = espEmu;
        };
        apps.build-firmware = flake-utils.lib.mkApp {
          drv = pkgs.writeShellApplication {
            name = "build-reterminal-e1002-firmware";
            runtimeInputs = [
              pkgs.nix
              pkgs.podman
              pkgs.git
              pkgs.python3
            ];
            text = ''export NOMMU_REPO=${./.}; exec ${./tools/build-firmware.sh} "''${1:-.work}"'';
          };
        };
        apps.test-emulator = flake-utils.lib.mkApp {
          drv = pkgs.writeShellApplication {
            name = "test-reterminal-emulator";
            runtimeInputs = [
              espEmu
              pkgs.coreutils
              pkgs.gnugrep
            ];
            text = ''exec ${./tools/test-emulator.sh} "''${1:?Usage: nix run .#test-emulator -- IMAGE.bin [LOG]}" "''${2:-.work/esp-emu.log}"'';
          };
        };
        checks.layout =
          pkgs.runCommand "reterminal-layout-check"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              python3 ${./tools/check-layout.py} ${./reterminal-e1002/partitions_32mb.csv} --flash-bytes 33554432
              python3 ${./tools/test-layout.py} ${./tools/check-layout.py}
              touch $out
            '';
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.python3
            pkgs.esptool
            pkgs.git
            pkgs.gnumake
            pkgs.gcc
            pkgs.cmake
            pkgs.ninja
            xipCramfs
            pkgs.cpio
            pkgs.fakeroot
            espEmu
          ];
          LINUX_ESP32_S3_SRC = sources.linux;
          SIXOS_SRC = sources.sixos;
          SIXOS_INIT = sixosInit;
          SIXOS_SERVICE_SOURCE = sixosServices;
          CRAMFSCK = "${xipCramfs}/bin/cramfsck";
          MKCRAMFS = "${xipCramfs}/bin/mkcramfs";
        };
      }
    );
}
