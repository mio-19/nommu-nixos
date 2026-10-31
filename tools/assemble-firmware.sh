#!/usr/bin/env bash
# Assemble the evaluated sixos configuration and its actual Nix runtime closure.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(realpath "${1:-$repo/.work}")
linux=${LINUX_ESP32_S3_SRC:?enter nix develop}
configuration=${SIXOS_CONFIGURATION:?build the sixos site configuration first}
cramfsck=${CRAMFSCK:?enter nix develop}
mkcramfs=${MKCRAMFS:?enter nix develop}
out="$work/firmware"
root="$out/root"
profile=/nix/var/nix/profiles/system
test ! -e "$out" || { echo "Output already exists: $out; choose a fresh build work directory" >&2; exit 1; }
configuration=$(readlink -f "$configuration")
base=$(readlink -f "$configuration/sw")
mkdir -p "$out"
"$cramfsck" -x "$root" "$linux/images/rootfs.cramfs"
# Put the upstream userspace and target stack in real store objects. The FHS
# entry points required by the existing kernel remain thin compatibility links.
for dir in bin sbin usr lib; do
  rm -rf "$root/$dir"
done
mkdir -p "$root/nix/store" "$root/nix/var/nix/profiles" "$root/sbin"
nix-store --query --requisites "$configuration" > "$out/store-paths"
while IFS= read -r store_path; do
  cp -a "$store_path" "$root/nix/store/"
done < "$out/store-paths"
ln -s "$configuration" "$root$profile"
ln -s "$base/bin" "$root/bin"
ln -s "$base/usr" "$root/usr"
ln -s "$base/lib" "$root/lib"
cp -a "$base/sbin/." "$root/sbin/"
chmod u+w "$root/sbin"
rm -f "$root/sbin/init"
cp -L "$configuration/boot/init" "$root/sbin/init"
chmod 755 "$root/sbin/init"
# Reject host ELFs, incomplete store references, and broken boot scripts before
# emitting an image. These checks apply to the exact tree that is flashed.
python3 "$repo/tools/check-rootfs.py" "$root"
fakeroot bash -eu -c 'chown -R 0:0 "$1"; exec "$2" -X -q "$1" "$3"' _ "$root" "$mkcramfs" "$out/rootfs.cramfs"
"$cramfsck" "$out/rootfs.cramfs"
mkdir "$out/images"
cp "$linux"/images/{bootloader.bin,partition-table.bin,network_adapter.bin,etc.jffs2,xipImage,home.jffs2} "$out/images/"
cp "$out/rootfs.cramfs" "$out/images/"
python3 "$repo/tools/check-layout.py" "$linux/new-files/esp-hosted/network_adapter/partition_table.esp32s3.16m8r" --flash-bytes 16777216 --images "$out/images"
esptool --chip esp32s3 merge-bin --flash-mode dio --flash-freq 80m --flash-size 16MB \
  --pad-to-size 16MB -o "$out/reterminal-e1002-six-init-experimental.bin" \
  0x0 "$out/images/bootloader.bin" 0x8000 "$out/images/partition-table.bin" \
  0x10000 "$out/images/network_adapter.bin" 0xd0000 "$out/images/etc.jffs2" \
  0x140000 "$out/images/xipImage" 0x540000 "$out/images/rootfs.cramfs" \
  0xcc0000 "$out/images/home.jffs2"
(cd "$out"; sha256sum reterminal-e1002-six-init-experimental.bin > SHA256SUMS)
echo "Built sixos site configuration image: $out; hardware verification pending."
