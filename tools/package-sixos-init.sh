#!/usr/bin/env bash
# Repack sixos' CPIO with its target closure rooted in /nix/store.
set -euo pipefail
tree=${1:?tree directory}
archive=${2:?output CPIO archive}
rc_init=${3:?fixed-root rc.init}
template=${4:?sixos template archive}
relocator=${5:?store path relocator}

cd "$tree"
cpio -id < "$template"
python3 "$relocator" .
# The catch-all logger FIFO is unusable on this NOMMU target, so stage one runs
# without it (-B) and its diagnostics go straight to the console.
sed -i 's| -N -- | -N -B -- |; s| -v 1 | -v 2 |' bin/init
# sixos hands off to the firmware's fixed Nix-store system activation script.
install -m 755 "$rc_init" scripts/rc.init
find . -print0 | cpio --null --create --format=newc > "$archive"
