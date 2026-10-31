#!/usr/bin/env bash
# Assemble an experimental sixos-stage-one image from a verified Linux SDK build.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(realpath "${1:-$repo/.work}")
linux=${LINUX_ESP32_S3_SRC:?enter nix develop}
init=${SIXOS_INIT:?enter nix develop}
services=${SIXOS_SERVICE_SOURCE:?enter nix develop}
cramfsck=${CRAMFSCK:?enter nix develop}
mkcramfs=${MKCRAMFS:?enter nix develop}
stack="$work/skarnet-build"
out="$work/firmware"
root="$out/root"
payload="$out/system-payload"
profile=/nix/var/nix/profiles/system
test ! -e "$out" || { echo "Output already exists: $out; choose a fresh build work directory" >&2; exit 1; }
test -x "$stack/target/usr/bin/s6-svscan"
test -x "$stack/host/usr/bin/s6-rc-compile"
mkdir -p "$out"
"$cramfsck" -x "$root" "$linux/images/rootfs.cramfs"
mkdir -p "$payload"
for dir in bin sbin usr; do
  mv "$root/$dir" "$payload/$dir"
done
# Keep the diagnostic/init environment within the upstream 7.5 MiB cramfs
# partition; these upstream development utilities are not boot dependencies.
for program in micropython socat make nano curl mmu-run fork-test \
  fork-test-dynamic process-test jobq programbench atfork-test; do
  rm -f "$payload/usr/bin/$program"
done
mkdir -p "$payload/boot" "$payload/usr/share/sixos/bin" "$payload/usr/libexec" "$out/rc-source"
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
  s6-supervise s6-svc s6-svlisten s6-svlisten1 s6-svscan s6-svscanctl s6-svwait
)
for binary in "${runtime_bins[@]}"; do
  install -m 755 "$stack/target/usr/bin/$binary" "$payload/usr/bin/$binary"
done
# s6-svscan's default limits reserve ~260 KiB of stack for its service and
# name tables, which overflows this NOMMU target's 64 KiB stack. Bound them.
mv "$payload/usr/bin/s6-svscan" "$payload/usr/bin/s6-svscan.real"
cat > "$payload/usr/bin/s6-svscan" <<'EOF'
#!/bin/sh
exec /usr/bin/s6-svscan.real -C 128 -L 64 "$@"
EOF
chmod 755 "$payload/usr/bin/s6-svscan"
for binary in s6-ftrigrd s6-rc-fdholder-filler s6-rc-oneshot-run; do
  install -m 755 "$stack/target/usr/libexec/$binary" "$payload/usr/libexec/$binary"
done
install -m 755 "$stack/target/usr/lib/libfork.so.0" "$payload/usr/lib/libfork.so.0"
rm -f "$payload/sbin/init"
install -m 755 "$init/init" "$payload/sbin/init"
install -m 644 "$init/s6-linux-init.cpio" "$payload/boot/"
install -m 644 "$init/COPYING.sixos" "$payload/usr/share/sixos/"
install -m 755 "$repo/firmware/early-setup" "$payload/usr/share/sixos/bin/early-setup"
cat > "$payload/bin/activate" <<EOF
#!/bin/bash
set -eu
mkdir -p /run
rm -f /run/current-system
ln -sfn "$profile" /run/current-system
"$profile/usr/bin/s6-rc-init" -d -c "$profile/usr/share/sixos/db" /run/service
"$profile/usr/bin/s6-rc" -v2 -up change default
EOF
chmod 755 "$payload/bin/activate"
# Shutdown uses busybox's applet path, independent of the distro symlink layout.
ln -sf /bin/busybox "$payload/bin/reboot"
cp -a "$services/." "$out/rc-source/"
"$stack/host/usr/bin/s6-rc-compile" "$payload/usr/share/sixos/db" "$out/rc-source"
# Add the completed, self-contained target tree to the host Nix store. The
# returned content-addressed path is the path used by the firmware at runtime.
system_store=$(nix store add --name reterminal-sixos-system "$payload")
test -d "$system_store"
mkdir -p "$root/nix/store" "$root/nix/var/nix/profiles"
cp -a "$system_store" "$root/nix/store/"
ln -s "$system_store" "$root/nix/var/nix/profiles/system"
for dir in bin sbin usr; do ln -s "$profile/$dir" "$root/$dir"; done
ln -s "$profile" "$root/run/current-system"
# ELF/ABI and dependency checks are mandatory before an image is emitted.
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
echo "Built experimental sixos stage-one image: $out; hardware verification pending."
