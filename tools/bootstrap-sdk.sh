#!/usr/bin/env bash
# Run only the pinned upstream SDK stage, using rootless Podman.
set -euo pipefail
repo=${LINUX_ESP32_S3_SRC:-$(nix eval --raw "${NOMMU_REPO:-$(dirname "$0")/..}#inputs.linux-esp32-s3-src.outPath")}
work=$(realpath -m "${1:-.work}")
mkdir -p "$work/Linux-on-esp32-S3"
# Keep SDK state outside the Nix store. Never overwrite an existing build tree.
if [[ ! -f $work/Linux-on-esp32-S3/build/bootstrap-sdk.sh ]]; then
  cp -a "$repo/." "$work/Linux-on-esp32-S3/"
  chmod -R u+w "$work/Linux-on-esp32-S3"
  python3 - "$work/Linux-on-esp32-S3/build/container-build.sh" "$work/Linux-on-esp32-S3/build/bootstrap-sdk.sh" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
marker = 'stage toolchain toolchain'
assert source.count(marker) == 1
Path(sys.argv[2]).write_text(source.split(marker)[0] + marker + '\n')
PY
fi
podman build --network host --build-arg BUILDER_UID="$(id -u)" --build-arg BUILDER_GID="$(id -g)" \
  -f "$work/Linux-on-esp32-S3/build/Dockerfile" -t localhost/nommu-six-build "$work/Linux-on-esp32-S3"
exec podman run --rm --userns=keep-id --user "$(id -u):$(id -g)" --network host \
  --volume "$work:/work" --env JOBS="${JOBS:-8}" \
  --entrypoint bash localhost/nommu-six-build build/bootstrap-sdk.sh
