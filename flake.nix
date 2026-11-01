{
  description = "reTerminal E1002 Xtensa/NOMMU firmware port workspace (sixos init)";
  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.zst";
    flake-utils.url = "github:numtide/flake-utils";
    linux-esp32-s3-src = {
      url = "github:paulneja/Linux-on-esp32-S3";
      flake = false;
    };
    sixos = {
      url = "git+https://codeberg.org/amjoseph/sixos.git";
      flake = false;
    };
    sixos-src = {
      url = "git+https://codeberg.org/amjoseph/sixos.git";
      flake = false;
    };
  };
  outputs =
    inputs@{ nixpkgs, flake-utils, ... }:
    {
      lib.sources.linux = inputs.linux-esp32-s3-src;
      lib.sources.sixos = inputs.sixos;
      lib.mkSixosSite =
        { system, stack }:
        import ./nix/sixos-site.nix {
          inherit system stack nixpkgs;
          sixos-src = inputs.sixos;
          linux-src = inputs.linux-esp32-s3-src;
        };
      lib.sixosModules = {
        reterminal-e1002 = ./reterminal-e1002/module.nix;
        default = ./reterminal-e1002/module.nix;
      };
      nixosModules.reterminal-e1002 = ./reterminal-e1002/module.nix;
      nixosModules.default = ./reterminal-e1002/module.nix;
      nixosConfigurations.reterminal-e1002 =
        let
          pkgs = import nixpkgs { system = "x86_64-linux"; };
        in
        pkgs.lib.evalModules {
          specialArgs = { inherit pkgs; };
          modules = [
            ./reterminal-e1002/module.nix
            ./configuration.nix
          ];
        };
      nixosConfigurations.default =
        let
          pkgs = import nixpkgs { system = "x86_64-linux"; };
        in
        pkgs.lib.evalModules {
          specialArgs = { inherit pkgs; };
          modules = [
            ./reterminal-e1002/module.nix
            ./configuration.nix
          ];
        };
    }
    // flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        sources = {
          linux = inputs.linux-esp32-s3-src;
          sixos = inputs.sixos;
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
              "E1002 board support and matched kernel/ESP-IDF flash layout"
              "Hardware boot, peripheral validation, and memory/resource measurements"
            ];
            revisions = builtins.mapAttrs (_: src: src.rev) sources;
          }
        );
        portingKit = pkgs.stdenvNoCC.mkDerivation {
          pname = "reterminal-e1002-porting-kit";
          version = "0.1.0";
          dontUnpack = true;
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/sources $out/docs $out/board $out/services
            ln -s ${sources.linux} $out/sources/linux-esp32-s3
            ln -s ${sources.sixos} $out/sources/sixos
            cp ${manifest} $out/port-status.json
            cp ${./README.md} $out/README.md
            cp ${./docs/porting.md} $out/docs/porting.md
            cp ${./reterminal-e1002/partitions_32mb.csv} $out/board/partitions_32mb.PROPOSED.csv
            cp ${./reterminal-e1002/esp32s3-reterminal-e1002.dts} $out/board/esp32s3-reterminal-e1002.dts
            cp ${./reterminal-e1002/README.md} $out/board/README.md
            cp ${./reterminal-e1002/module.nix} $out/board/module.nix
            cp -r ${./reterminal-e1002/services}/. $out/services/
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "Porting kit, DTS, partition layout, and peripheral services for Seeed reTerminal E1002";
            homepage = "https://github.com/mio-19/nommu-nixos";
            license = licenses.mit;
            platforms = platforms.all;
          };
        };
        sixosInit =
          if pkgs.stdenv.hostPlatform.isLinux then
            import ./nix/sixos-init.nix {
              inherit pkgs;
              sixos-src = sources.sixos;
            }
          else
            null;
        xipCramfs = import ./nix/xip-cramfs.nix { inherit pkgs; };
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
        espEmu =
          if espEmuAssets ? ${system} then
            pkgs.stdenvNoCC.mkDerivation {
              pname = "esp-emu";
              version = "0.51.0";
              src = pkgs.fetchurl {
                url = "https://github.com/espressif/esp-emulator/releases/download/v0.51.0/${espEmuAssets.${system}.file}";
                inherit (espEmuAssets.${system}) hash;
              };
              dontUnpack = true;
              nativeBuildInputs = [ pkgs.gnutar ];
              installPhase = ''
                runHook preInstall
                mkdir -p $out/bin
                tar -xzf $src --strip-components=1 -C $out/bin
                chmod 755 $out/bin/esp-emu
                runHook postInstall
              '';
              meta = with pkgs.lib; {
                description = "Espressif chip emulator for ESP32 family";
                homepage = "https://github.com/espressif/esp-emulator";
                license = licenses.asl20;
                platforms = [
                  "x86_64-linux"
                  "aarch64-linux"
                  "aarch64-darwin"
                ];
                mainProgram = "esp-emu";
              };
            }
          else
            null;
        skarnetSources =
          pkgs.runCommand "skarnet-pinned-sources"
            {
              nativeBuildInputs = [
                pkgs.gnutar
                pkgs.gzip
              ];
              meta = with pkgs.lib; {
                description = "Pinned Skarnet sources (skalibs, execline, s6, s6-rc, s6-linux-init, s6-portable-utils)";
                homepage = "https://skarnet.org/software/";
                license = licenses.isc;
                platforms = platforms.all;
              };
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
                    "s6-portable-utils"
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
            runHook preInstall
            mkdir -p $out
            cp reference.bin $out/esp32s3-16mb-upstream-reference.bin
            cp ${manifest} $out/port-status.json
            echo 'Upstream prebuilt 16MB devkit reference only. No sixos. E1002 untested.' > $out/README
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "Prebuilt 16MB reference firmware image for ESP32-S3 from Linux-on-esp32-S3";
            homepage = "https://github.com/paulneja/Linux-on-esp32-S3";
            license = licenses.gpl2Plus;
            platforms = platforms.all;
          };
        };
      in
      {
        packages = {
          default = portingKit;
          porting-kit = portingKit;
          upstream-reference = upstreamReference;
          skarnet-sources = skarnetSources;
          cramfs-xip = xipCramfs;
        }
        // pkgs.lib.optionalAttrs (sixosInit != null) {
          sixos-init = sixosInit;
        }
        // pkgs.lib.optionalAttrs (espEmu != null) {
          esp-emu = espEmu;
        };
        apps = {
          build-firmware =
            (flake-utils.lib.mkApp {
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
            })
            // {
              meta = {
                description = "Build pinned SDK, target Skarnet packages, sixos site, and flash image";
              };
            };
          test-sixos =
            (flake-utils.lib.mkApp {
              drv = pkgs.writeShellApplication {
                name = "test-reterminal-sixos";
                runtimeInputs = [
                  pkgs.bash
                  pkgs.python3
                  pkgs.coreutils
                ];
                text = ''export NOMMU_REPO="''${NOMMU_REPO:-$PWD}"; exec ${./tools/test-sixos.sh} "''${1:?Usage: nix run .#test-sixos -- IMAGE.bin [LOG]}" "''${2:-.work/sixos-boot.log}"'';
              };
            })
            // {
              meta = {
                description = "Boot and test sixos init, service bundle, and login prompt under esp32sim";
              };
            };
          flash-firmware =
            (flake-utils.lib.mkApp {
              drv = pkgs.writeShellApplication {
                name = "flash-reterminal-firmware";
                runtimeInputs = [
                  pkgs.esptool
                  pkgs.coreutils
                ];
                text = ''
                  port="''${1:?Usage: nix run .#flash-firmware -- PORT [IMAGE.bin] (e.g. /dev/ttyACM0)}"
                  image="''${2:-.work/firmware/reterminal-e1002-six-init-experimental.bin}"
                  if [[ ! -f "$image" ]]; then
                    echo "Image not found: $image" >&2
                    exit 1
                  fi
                  bytes=$(stat -c%s "$image" 2>/dev/null || wc -c < "$image")
                  flash_size="16MB"
                  if (( bytes > 16777216 )); then
                    flash_size="32MB"
                  fi
                  echo "Flashing $image ($flash_size) to $port at 460800 baud..."
                  exec esptool --chip esp32s3 -p "$port" -b 460800 write_flash \
                    --flash-mode dio --flash-size "$flash_size" --flash-freq 80m \
                    0x0 "$image"
                '';
              };
            })
            // {
              meta = {
                description = "Flash merged ESP32-S3 firmware image to board serial port using esptool";
              };
            };
        }
        // pkgs.lib.optionalAttrs (espEmu != null) {
          test-emulator =
            (flake-utils.lib.mkApp {
              drv = pkgs.writeShellApplication {
                name = "test-reterminal-emulator";
                runtimeInputs = [
                  espEmu
                  pkgs.coreutils
                  pkgs.gnugrep
                ];
                text = ''exec ${./tools/test-emulator.sh} "''${1:?Usage: nix run .#test-emulator -- IMAGE.bin [LOG]}" "''${2:-.work/esp-emu.log}"'';
              };
            })
            // {
              meta = {
                description = "Boot merged image in Espressif esp-emu (stops before Linux network adapter)";
              };
            };
        };
        checks = {
          layout =
            pkgs.runCommand "reterminal-layout-check"
              {
                nativeBuildInputs = [ pkgs.python3 ];
                meta = with pkgs.lib; {
                  description = "Validate proposed 32MB partition table bounds, layout, and offsets";
                };
              }
              ''
                python3 ${./tools/check-layout.py} ${./reterminal-e1002/partitions_32mb.csv} --flash-bytes 33554432
                python3 ${./tools/test-layout.py} ${./tools/check-layout.py}
                touch $out
              '';
          syntax =
            pkgs.runCommand "reterminal-scripts-syntax-check"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.dash
                  pkgs.python3
                ];
                meta = with pkgs.lib; {
                  description = "Validate Python AST and dash/bash shell script syntax across repository";
                };
              }
              ''
                python3 -c "import ast, glob; [ast.parse(open(f, 'rb').read(), f) for f in glob.glob('${./tools}/*.py')]"
                for script in ${./tools}/*.sh ${./firmware}/* ${./reterminal-e1002/services}/*/run; do
                  if [[ -f "$script" && "$script" != *.py && "$script" != *__pycache__* ]]; then
                    bash -n "$script" 2>/dev/null || dash -n "$script"
                  fi
                done
                touch $out
              '';
          nixos-module =
            let
              eval = pkgs.lib.evalModules {
                specialArgs = { inherit pkgs; };
                modules = [
                  ./reterminal-e1002/module.nix
                  ./configuration.nix
                ];
              };
            in
            pkgs.runCommand "reterminal-nixos-module-check"
              {
                meta = with pkgs.lib; {
                  description = "Verify NixOS module evaluation and type compliance via lib.evalModules";
                };
              }
              ''
                test "${eval.config.boot.loader.esp-idf.chip}" = "esp32s3"
                test "${eval.config.hardware.reterminal-e1002.deviceTree.name}" = "esp32s3-reterminal-e1002.dtb"
                test "${eval.config.networking.hostName}" = "reterminal-e1002"
                touch $out
              '';
        }
        // pkgs.lib.optionalAttrs (sixosInit != null) {
          sixos-init = sixosInit;
        };
        formatter = pkgs.writeShellApplication {
          name = "format-nix";
          runtimeInputs = [
            pkgs.nixfmt
            pkgs.git
          ];
          text = ''
            while IFS= read -r -d "" file; do
              if [[ -f "$file" ]]; then
                nixfmt "$@" "$file"
              fi
            done < <(git ls-files -z --cached --others --exclude-standard -- '*.nix')
          '';
        };
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
          ]
          ++ pkgs.lib.optional (espEmu != null) espEmu;
          LINUX_ESP32_S3_SRC = sources.linux;
          SIXOS_SRC = sources.sixos;
          SIXOS_INIT = sixosInit;
          CRAMFSCK = "${xipCramfs}/bin/cramfsck";
          MKCRAMFS = "${xipCramfs}/bin/mkcramfs";
          meta = with pkgs.lib; {
            description = "Development environment for Xtensa ESP32-S3 firmware and sixos porting";
          };
        };
      }
    );
}
