#!/usr/bin/env bash
# Repack sixos' CPIO with its target closure rooted in /nix/store.
set -euo pipefail
tree=${1:?tree directory}
archive=${2:?output CPIO archive}
rc_init=${3:?fixed-root rc.init}
template=${4:?sixos template archive}
relocator=${5:?store path relocator}
metadata=${6:?newc metadata transformer}

cd "$tree"
python3 "$metadata" < "$template" | cpio -id --no-preserve-owner
python3 "$relocator" .
# Extract without fakeroot: a second fakeroot session turns the archive's
# FIFOs into regular placeholder files on this host. Empty regular files make
# shutdownd read EOF continuously and prevent the catch-all logger working.
for fifo in run-image/service/{s6-linux-init-shutdownd,s6-svscan-log}/fifo; do
  test -p "$fifo" || { echo "Init FIFO was not preserved: $fifo" >&2; exit 1; }
done
sed -i 's| -v 1 | -v 2 |; s|/usr/bin|/nix/var/nix/profiles/system/bin|g; s|/usr/sbin|/nix/var/nix/profiles/system/bin|g; s|/usr/libexec|/nix/var/nix/profiles/system/libexec|g' bin/init
# sixos hands off to the firmware's fixed Nix-store system activation script.
install -m 755 "$rc_init" scripts/rc.init
find . -print0 | cpio --null --create --format=newc --owner=0:0 | python3 "$metadata" "$template" > "$archive"
