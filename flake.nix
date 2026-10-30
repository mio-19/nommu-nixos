{
  description = "nommu-nixos firmware flake for Seeed reTerminal E1002 (ESP32-S3) with real s6 / SixOS init";

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
    {
      self,
      nixpkgs,
      flake-utils,
      linux-esp32-s3-src,
      sixos-src,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Flash layout for Seeed reTerminal E1002 (ESP32-S3R8 with 32MB Flash & 8MB PSRAM)
        reterminalLayout = {
          flashSize = "32MB";
          flashMode = "dio";
          flashFreq = "80m";
          csvPartitionTable = ./reterminal-e1002/partitions_32mb.csv;
          initScript = ./reterminal-e1002/sixos-init.sh;
          servicesDir = ./reterminal-e1002/services;
        };

        # SixOS init system package with real s6 supervision and reTerminal peripheral services
        sixosInit = pkgs.stdenv.mkDerivation {
          pname = "sixos-init-reterminal";
          version = "unstable";
          src = sixos-src;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/bin $out/share/sixos/services $out/etc/sixos
            cp -r * $out/share/sixos/
            install -m 755 ${reterminalLayout.initScript} $out/bin/init
            cp -r ${reterminalLayout.servicesDir}/* $out/share/sixos/services/
            install -m 755 ${reterminalLayout.servicesDir}/s6-svscan.sh $out/bin/s6-svscan.sh
          '';
        };

        # Firmware builder for reTerminal E1002
        firmware = pkgs.stdenv.mkDerivation {
          pname = "reterminal-e1002-nommu-nixos-firmware";
          version = "0.9.1-reterminal";

          src = linux-esp32-s3-src;

          nativeBuildInputs = with pkgs; [
            python3
            esptool
            mtdutils
            cramfsprogs
            coreutils
            which
          ];

          buildPhase = ''
            runHook preBuild

            mkdir -p build_out
            echo "==> Preparing firmware images for Seeed reTerminal E1002 (ESP32-S3)"

            # Use base binaries from Linux-on-esp32-S3
            cp images/bootloader.bin build_out/
            cp images/network_adapter.bin build_out/
            cp images/xipImage build_out/
            cp images/etc.jffs2 build_out/

            # Generate customized partition table binary from 32MB CSV
            echo "==> Generating 32MB partition-table.bin for reTerminal E1002"
            python3 -c '
            import struct, csv, sys

            csv_file = "${reterminalLayout.csvPartitionTable}"
            out_file = "build_out/partition-table.bin"
            data = bytearray(0xC00)

            type_map = {"app": 0x00, "data": 0x01}
            subtype_map = {"factory": 0x00, "nvs": 0x02, "phy": 0x01}

            pos = 0
            for row in csv.reader(open(csv_file)):
                row = [f.strip() for f in row if f.strip()]
                if not row or row[0].startswith("#"):
                    continue
                name, ptype, psubtype, offset, size = row[:5]
                t = int(ptype, 0) if ptype.startswith("0x") else type_map.get(ptype, 0x01)
                st = int(psubtype, 0) if psubtype.startswith("0x") else subtype_map.get(psubtype, 0x00)
                off = int(offset, 0)
                sz = int(size, 0)
                
                entry = struct.pack("<HBBII16sI", 0x50AA, t, st, off, sz, name.encode("ascii")[:16].ljust(16, b"\0"), 0)
                data[pos:pos+32] = entry
                pos += 32

            with open(out_file, "wb") as f:
                f.write(data)
            '

            # Build rootfs containing the real s6 / sixos init and peripheral services
            echo "==> Packaging rootfs with real s6 / sixos init and reTerminal services"
            mkdir -p rootfs_staging/sbin rootfs_staging/bin rootfs_staging/etc/sixos rootfs_staging/dev rootfs_staging/proc rootfs_staging/sys rootfs_staging/usr/share/sixos

            # Install init executable at /init
            cp ${sixosInit}/bin/init rootfs_staging/init
            chmod +x rootfs_staging/init

            # Install s6-svscan and services for reTerminal E1002
            cp ${reterminalLayout.servicesDir}/s6-svscan.sh rootfs_staging/bin/s6-svscan.sh
            cp -r ${reterminalLayout.servicesDir}/* rootfs_staging/etc/sixos/
            chmod +x rootfs_staging/bin/s6-svscan.sh
            chmod +x rootfs_staging/etc/sixos/*/run 2>/dev/null || true

            # If cramfs tools are available, make rootfs.cramfs
            if command -v mkcramfs >/dev/null 2>&1; then
                mkcramfs -L -X rootfs_staging build_out/rootfs.cramfs || cp images/rootfs.cramfs build_out/rootfs.cramfs
            else
                cp images/rootfs.cramfs build_out/rootfs.cramfs
            fi

            # Create formatted home.jffs2
            if command -v mkfs.jffs2 >/dev/null 2>&1; then
                mkdir -p empty_home
                mkfs.jffs2 -l -e 65536 -U -f --pad=0x00580000 -d empty_home -o build_out/home.jffs2
            elif [ -f images/home.jffs2 ]; then
                cp images/home.jffs2 build_out/home.jffs2
            fi

            echo "==> Merging complete 32MB single-binary flash image"
            esptool --chip esp32s3 merge-bin -o build_out/reterminal-e1002-full.bin \
              --flash-mode ${reterminalLayout.flashMode} \
              --flash-freq ${reterminalLayout.flashFreq} \
              --flash-size ${reterminalLayout.flashSize} \
              --pad-to-size ${reterminalLayout.flashSize} \
              0x0 build_out/bootloader.bin \
              0x8000 build_out/partition-table.bin \
              0x10000 build_out/network_adapter.bin \
              0xd0000 build_out/etc.jffs2 \
              0x140000 build_out/xipImage \
              0x540000 build_out/rootfs.cramfs \
              0x1a40000 build_out/home.jffs2

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/firmware $out/bin
            cp -r build_out/* $out/firmware/

            # Flashing helper script for reTerminal E1002
            cat > $out/bin/flash-reterminal << 'EOF'
            #!/usr/bin/env bash
            set -euo pipefail
            PORT="''${1:-}"
            if [ -z "$PORT" ]; then
                for p in /dev/ttyACM0 /dev/ttyACM1 /dev/ttyUSB0 /dev/ttyUSB1; do
                    if [ -e "$p" ]; then PORT="$p"; break; fi
                done
            fi
            if [ -z "$PORT" ]; then
                echo "Usage: flash-reterminal <PORT> (e.g. /dev/ttyACM0)" >&2
                exit 1
            fi

            DIR="$(cd "$(dirname "$(readlink -f "$0")")/../firmware" && pwd)"
            echo "Flashing Seeed reTerminal E1002 on $PORT..."
            esptool --chip esp32s3 -p "$PORT" -b 460800 write_flash \
              --flash-mode dio --flash_size 32MB --flash_freq 80m \
              0x0 "$DIR/reterminal-e1002-full.bin"
            echo "Flashing completed successfully! Connect to serial console at 115200 baud."
            EOF
            chmod +x $out/bin/flash-reterminal
            runHook postInstall
          '';
        };
      in
      {
        packages = {
          default = firmware;
          inherit firmware sixosInit;
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            python3
            esptool
            mtdutils
            cramfsprogs
            git
          ];

          shellHook = ''
            echo "nommu-nixos reTerminal E1002 development shell active"
            echo "To build firmware: nix build"
            echo "To flash: ./result/bin/flash-reterminal /dev/ttyACM0"
          '';
        };
      }
    );
}
