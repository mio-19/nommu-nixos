{
  description = "Nix flake to build Linux on ESP32‑S3 firmware for Seeed reTerminal E1002";

  inputs = {
    # Nixpkgs unstable, fetched from the official tarball URL
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.zst";
    flake-utils.url = "github:numtide/flake-utils";
    # ESP-IDF development environment overlay
    esp-dev.url = "github:mirrexagon/nixpkgs-esp-dev";
  };

  outputs = { self, nixpkgs, flake-utils, esp-dev, ... }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs { inherit system; };
      espIdf = esp-dev.packages.${system}.esp-idf; # Provides esp-idf with toolchain
      overlay = final: prev: {
        linuxEsp32Firmware = pkgs.stdenv.mkDerivation {
          pname = "linux-esp32-s3-firmware";
          version = "1.0";

          src = pkgs.fetchFromGitHub {
            owner = "paulneja";
            repo = "Linux-on-esp32-S3";
            rev = "<commit-hash>"; # replace with specific commit for reproducibility
            sha256 = pkgs.lib.fakeSha256; # replace after first attempt
          };

          nativeBuildInputs = [ pkgs.makeWrapper pkgs.gcc pkgs.gnumake pkgs.cmake espIdf.toolchain ];
          buildPhase = ''
            export CROSS_COMPILE=${espIdf.toolchain}/bin/xtensa-esp32s3-elf-
            make -C $src all
          '';
          installPhase = ''
            mkdir -p $out
            cp $src/build/*.bin $out/
          '';
        };
      };
    in {
      packages = {
        default = (import nixpkgs { inherit system; overlays = [ overlay ]; }).linuxEsp32Firmware;
      };
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [ espIdf.toolchain pkgs.gnumake pkgs.cmake ];
        shellHook = ''
          echo "Development environment for ESP32‑S3 firmware"
        '';
      };
    });
}
