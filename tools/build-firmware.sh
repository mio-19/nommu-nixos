#!/usr/bin/env bash
# Build the pinned SDK, cross-compiled s6 stack and experimental image in .work/.
set -euo pipefail
repo=${NOMMU_REPO:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}
work=$(realpath -m "${1:-$repo/.work}")
mkdir -p "$work"
# Refuse an existing artifact before bootstrapping or recompiling the SDK stack.
if [[ -e $work/firmware ]]; then
  echo "Output already exists: $work/firmware; preserve or rename it before rebuilding" >&2
  exit 1
fi
if [[ ! -x $work/cramfs-tools/bin/cramfsck ]]; then
  nix build "$repo#cramfs-xip" --no-link --print-out-paths > "$work/cramfs-tools-path"
  ln -s "$(cat "$work/cramfs-tools-path")" "$work/cramfs-tools"
fi
source="$work/Linux-on-esp32-S3"
sdk="$work/refs/esp32-linux-build/build/crosstool-NG/builds/xtensa-esp32s3-linux-uclibcfdpic"
root="$work/upstream-rootfs"
stack="$work/skarnet-build"
system=$(nix eval --raw --impure --expr builtins.currentSystem)
dev_shell="$repo#devShells.$system.default"
if [[ ! -x $sdk/bin/xtensa-esp32s3-linux-uclibcfdpic-gcc ]]; then
  "$repo/tools/bootstrap-sdk.sh" "$work"
fi
if [[ ! -d $work/skarnet-sources/s6-portable-utils ]]; then
  nix build "$repo#skarnet-sources" --no-link --print-out-paths > "$work/skarnet-source-path"
  ln -sfn "$(cat "$work/skarnet-source-path")" "$work/skarnet-sources"
fi
if [[ ! -d $root/usr ]]; then
  if [[ -d $root ]]; then
    rmdir "$root" || { echo "Partial rootfs exists at $root; remove it before retrying" >&2; exit 1; }
  fi
  "$work/cramfs-tools/bin/cramfsck" -x "$root" "$source/images/rootfs.cramfs"
fi
nix develop "$dev_shell" -c bash "$repo/tools/build-skarnet.sh" "$sdk" "$stack" "$work/skarnet-sources" "$root" "$source"
# Snapshot the completed cross-build as an input to the full sixos site.
# Only the runtime outputs enter the configuration's runtime closure.
nix store add --name esp32s3-skarnet-build "$stack" > "$work/stack-store-path"
export SIXOS_CONFIGURATION
SIXOS_CONFIGURATION=$(nix build --impure --file "$repo/nix/build-configuration.nix" \
  --argstr repo "$repo" --argstr stack "$(cat "$work/stack-store-path")" \
  --no-link --print-out-paths)
export LINUX_ESP32_S3_SRC="$source"
export CRAMFSCK="$work/cramfs-tools/bin/cramfsck"
export MKCRAMFS="$work/cramfs-tools/bin/mkcramfs"
export PATH="$work/cramfs-tools/bin:$PATH"
nix develop "$dev_shell" -c bash "$repo/tools/assemble-firmware.sh" "$work"
