#!/usr/bin/env bash
# Boot the complete site configuration, not just the Linux kernel banner.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
image=${1:?Usage: test-sixos.sh IMAGE.bin [LOG]}
log=${2:-$repo/.work/sixos-boot.log}
emulator=${ESP32SIM:-$repo/.work/esp32sim/esp32sim}
rom=${ESP32SIM_ROM:-$repo/.work/esp32sim-roms/esp32s3_rev0_rom.elf}
test -x "$emulator"
test -f "$rom"
mkdir -p "$(dirname "$log")"
options=(--max-seconds 20)
if [[ ${SIXOS_TEST_LIFECYCLE:-0} == 1 ]]; then
  options=(--max-seconds 40 --script "$repo/tools/sixos-lifecycle.script")
fi
# The stub is specific to nimble_port_init in the pinned network adapter.
# It bypasses BLE provisioning only; Linux and sixos execute unchanged.
timeout "${SIXOS_TEST_TIMEOUT:-180s}" "$emulator" --chip s3 --boot rom --rom "$rom" \
  --flash-image "$image" --flash-mb 16 --psram-mb 8 --board none \
  --console uart0 "${options[@]}" --no-reboot --stub 0x4200ed50=0xffffffff \
  --wifi 'ssid=esp32sim,chan=6,psk=esp32sim-password' --net none > "$log" 2>&1
python3 - "$log" <<'PY'
from pathlib import Path
import os
import re
import sys
log = Path(sys.argv[1]).read_text()
for marker in ('Linux version', 's6-linux-init version', 'login:'):
    if marker not in log:
        raise SystemExit(f'Missing boot marker: {marker}; see {sys.argv[1]}')
for service in ('early-setup', 'hwclock-fake', 'hwclock-fake-updater', 'console'):
    marker = f'service {service} successfully started'
    if log.count(marker) != 1:
        raise SystemExit(f'Expected exactly one successful start of {service}; see {sys.argv[1]}')
for marker in ('Kernel panic', 'Oops:', 'unable to exec', 'error:', 'fatal:', 'Allocation of length', 'page allocation failure',
               'warning: unable to stop service'):
    if marker in log:
        raise SystemExit(f'Boot failure: {marker}; see {sys.argv[1]}')
if os.environ.get('SIXOS_TEST_LIFECYCLE') == '1':
    clean = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', log).replace('\r', '')
    if 'SIXOS-REACTIVATE-OK' not in clean.splitlines():
        raise SystemExit('Repeat activation did not complete successfully')
    for service in ('console', 'early-setup', 'hwclock-fake', 'hwclock-fake-updater',
                    's6rc-oneshot-runner'):
        marker = f'service {service} successfully stopped'
        if log.count(marker) != 1:
            raise SystemExit(f'Expected exactly one successful stop of {service}')
    for marker in ('uid=0(root)', 'passwd: password for root changed by root',
                   'reboot: Restarting system', '[emu] stop: SwReset'):
        if marker not in log:
            raise SystemExit(f'Missing lifecycle marker: {marker}')
    print('Root login, repeat activation, clock-save shutdown and software reboot verified')
print(f'Linux, sixos activation, all site services and UART login verified: {sys.argv[1]}')
PY
