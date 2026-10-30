#!/usr/bin/env bash
# Boot a merged image in Espressif's ESP32-S3 emulator and require Linux output.
set -euo pipefail
image=${1:?Usage: test-emulator.sh merged-image.bin [log-file]}
log=${2:-.work/esp-emu.log}
timeout=${ESP_EMU_TIMEOUT:-60s}
mkdir -p "$(dirname "$log")"
rm -f "$log"
set +e
esp-emu --chip esp32s3 --psram-size 8M --console uart0 \
  --timeout "$timeout" --exit-on 'Linux version' --firmware "$image" \
  2>&1 | tee "$log"
emulator_status=${PIPESTATUS[0]}
set -e
if grep -q 'Linux version' "$log"; then
  echo "Linux boot banner observed in emulator output ($log)."
  exit 0
fi
if grep -q 'task_wdt: Aborting' "$log"; then
  echo "ESP32-S3 firmware watchdog reset before Linux output; see $log." >&2
else
  echo "Linux boot banner not observed before emulator exit; see $log." >&2
fi
if ((emulator_status != 0)); then
  echo "esp-emu exited with status $emulator_status." >&2
fi
exit 1
