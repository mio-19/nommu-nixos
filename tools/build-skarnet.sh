#!/usr/bin/env bash
# Build a matched host/target skarnet stack against the upstream Linux SDK.
set -euo pipefail
sdk=${1:?Usage: build-skarnet.sh SDK_DIR OUTPUT_DIR SOURCE_DIR ROOTFS_DIR}
out=$(realpath -m "${2:?output directory}")
sources=$(realpath "${3:?source directory}")
prefix="$sdk/bin/xtensa-esp32s3-linux-uclibcfdpic"
rootfs=$(realpath "${4:?extracted upstream rootfs}")
linuxSource=$(realpath "${5:?Linux-on-esp32-S3 source tree}")
xtensaConfig=${XTENSA_GNU_CONFIG:-"$(dirname "$sdk")/../../xtensa-dynconfig/esp32s3.so"}
test -f "$xtensaConfig" || { echo "Missing ESP32-S3 Xtensa configuration: $xtensaConfig" >&2; exit 1; }
xtensaConfig=$(realpath "$xtensaConfig")
if [[ ${BUILD_SIDES:-host target} == *target* ]]; then test -x "$prefix-gcc"; fi
test -f "$rootfs/usr/lib/libfork.so.0"
mkdir -p "$out/host" "$out/target" "$out/build"
mkdir -p "$out/target/usr/include"
mkdir -p "$out/target/usr/lib"
cat > "$out/target/usr/include/libfork-decls.h" <<'EOF'
/* uClibc omits the fork prototype for NOMMU; libfork supplies this symbol. */
extern int fork(void);
EOF
XTENSA_GNU_CONFIG="$xtensaConfig" "$prefix-gcc" -std=c99 -Os -mfdpic -mauto-litpools -fPIC -shared \
  -Wl,-soname,libfork.so.0 \
  "$linuxSource/experiments/mmu-poc/fork/fork-compat.c" \
  -o "$out/target/usr/lib/libfork.so.0"
# Cross configure must use supplied target sysdeps, never host feature probes.
for side in ${BUILD_SIDES:-host target}; do
  for package in skalibs execline s6 s6-rc s6-linux-init; do
    build="$out/build/$side-$package"
    mkdir -p "$build"
    cp -a "$sources/$package/." "$build/"
    chmod -R u+w "$build"
    cd "$build"
    options=(--prefix=/usr --libdir=/usr/lib
      --includedir=/usr/include --disable-shared)
    if [[ $side == target ]]; then
      export CC="$prefix-gcc" AR="$prefix-ar" RANLIB="$prefix-ranlib" STRIP="$prefix-strip"
      export XTENSA_GNU_CONFIG="$xtensaConfig"
      export CFLAGS="-Os -mfdpic -mauto-litpools -fPIC -D_BSD_SOURCE -ffunction-sections -fdata-sections -include $out/target/usr/include/libfork-decls.h"
      export LDFLAGS='-Wl,--gc-sections,-z,stack-size=65536'
      export LDLIBS="-Wl,--no-as-needed -L$rootfs/usr/lib -l:libfork.so.0 -Wl,--as-needed"
      options+=(--host=xtensa-esp32s3-linux-uclibcfdpic)
    else
      export CC=gcc AR=ar RANLIB=ranlib STRIP=strip
      unset CFLAGS LDFLAGS LDLIBS
    fi
    if [[ $package == skalibs && $side == target ]]; then
      options+=(--with-sysdep-devurandom=yes --with-sysdep-posixspawnearlyreturn=no --with-sysdep-posixspawn=no
        --with-sysdep-procselfexe=/proc/self/exe --with-sysdep-selectinfinite=yes)
    fi
    if [[ $package != skalibs ]]; then
      options+=(--bindir=/usr/bin)
      options+=(--with-sysdeps="$out/$side/usr/lib/skalibs/sysdeps"
        --with-include="$out/$side/usr/include" --with-lib="$out/$side/usr/lib")
    fi
    ./configure "${options[@]}"
    make -j"${JOBS:-8}" LDLIBS="${LDLIBS:-}"
    make DESTDIR="$out/$side" LDLIBS="${LDLIBS:-}" install
  done
 done
