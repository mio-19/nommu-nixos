{
  description = "Nix flake to build Linux on ESP32‑S3 firmware for Seeed reTerminal E1002";

  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.zst";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs { inherit system; };
      espIdfPkg = (builtins.getFlake "github:mirrexagon/nixpkgs-esp-dev").outputs.packages.${system}.esp-idf-esp32s3;
    in {
      packages = {
        default = pkgs.stdenv.mkDerivation {
          pname = "linux-esp32-s3-firmware";
          version = "1.0";

          src = pkgs.fetchFromGitHub {
            owner = "paulneja";
            repo = "Linux-on-esp32-S3";
            rev = "<commit-hash>"; # replace with specific commit for reproducibility
            sha256 = pkgs.lib.fakeSha256; # replace after first attempt
          };

          nativeBuildInputs = [ pkgs.makeWrapper pkgs.gcc pkgs.gnumake pkgs.cmake espIdfPkg.toolchain ];

          buildPhase = ''
            export CROSS_COMPILE=${espIdfPkg.toolchain}/bin/xtensa-esp32s3-elf-
            make -C $src all
          '';

          installPhase = ''
            mkdir -p $out
            cp $src/build/*.bin $out/
          '';
        };
      };
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [ espIdfPkg.toolchain pkgs.gnumake pkgs.cmake ];
        shellHook = ''
          echo "Development environment for ESP32‑S3 firmware"
        '';
      };
    });
}
