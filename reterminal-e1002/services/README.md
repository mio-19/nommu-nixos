# Seeed reTerminal E1002 Hardware Services

This directory contains s6 service supervision definitions for the Seeed reTerminal E1002 (ESP32-S3):

1. **`buttons/run`**: Monitors user buttons (Left GPIO3, Middle GPIO4, Right GPIO5), controls the status LED (GPIO6, active low), and triggers the feedback buzzer (GPIO45). Dispatches display commands (`refresh`, `status`, `next`) to the ePaper daemon.
2. **`epaper/run`**: Daemon for the 7.3-inch 800x480 Spectra 6 (6-color) ED2208 ePaper display on SPI2 (GPIO7/9/10/11/12/13). Listens on the command pipe `/run/epaper/cmd` and renders dashboard views.
3. **`sensors/run`**: Polling daemon for the on-board Sensirion SHT40 temperature/humidity sensor (I2C0 address 0x44), NXP PCF8563 RTC (I2C0 address 0x51), and battery voltage ADC (GPIO1). Exports telemetry to `/run/sensors/metrics.json`.

## Supervision Architecture

These services run under s6 supervision:
- When activated, each service runs in the foreground and outputs logs to standard error.
- Signal handling (TERM, INT, HUP) performs graceful hardware reset (turning off LEDs and buzzer, removing FIFOs).
- In sixos, services are mapped to `targets.reterminal` or activated as longrun services when board bring-up is selected.
