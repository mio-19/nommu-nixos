# Seeed reTerminal E1002 Hardware Services

This directory contains s6 service supervision definitions for Seeed reTerminal E1002 (ESP32-S3 NOMMU on sixos), matching functional parity with the factory/official Seeed firmware:

1. **`buttons/run`**: Monitors user buttons (Left/Green GPIO3, Middle GPIO4, Right GPIO5), controls the status LED (GPIO6, active low), and triggers the feedback buzzer (GPIO45).
   - **Short press Green (GPIO3)**: Refreshes ePaper display with audio chirp feedback.
   - **Long press Green (GPIO3, 5s)**: Triggers Spectra 6 anti-ghosting clearing sequence with double-chirp and LED pulse (factory firmware behavior).
   - **Middle button (GPIO4)**: Toggles telemetry and system diagnostics.
   - **Right button (GPIO5)**: Cycles dashboard view.
2. **`epaper/run`**: Daemon for the 7.3-inch 800x480 Spectra 6 (6-color) ED2208 ePaper display on SPI2 (GPIO7/9/10/11/12/13).
   - Listens on `/run/epaper/cmd` FIFO.
   - Supports `refresh`, `clear` (anti-ghosting multi-pass waveform), `status`, `image <path>`, and `text <msg>`.
3. **`sensors/run`**: Polling daemon for hardware telemetry and time management:
   - Sensirion SHT40 temperature/humidity sensor (I2C0 address 0x44).
   - NXP PCF8563 RTC (I2C0 address 0x51) hardware clock synchronization (`/dev/rtc0`).
   - Battery ADC monitoring on GPIO 1: Calculates battery voltage and State of Charge (SoC 0-100%) for the 2000 mAh Li-ion cell and detects USB charging.
   - Exports telemetry to `/run/sensors/metrics.json`.
4. **`web/run`**: Embedded HTTP server and REST API daemon (parity with SenseCraft HMI, Seeedash, and TRMNL):
   - Serves an interactive responsive web dashboard on port 8080 showing live temperature, humidity, battery level, RTC time, memory, and uptime.
   - REST API endpoints:
     - `GET /cgi-bin/api`: Live JSON sensor and system metrics.
     - `POST /cgi-bin/refresh`: Trigger remote ePaper refresh.
     - `POST /cgi-bin/clear`: Trigger anti-ghosting screen clear.
     - `POST /cgi-bin/beep`: Sound acoustic feedback buzzer.
5. **`sdcard/run`**: MicroSD card auto-mounter on SPI3 (GPIO14/15/16/46), mounting `/dev/mmcblk0*` to `/media/sdcard`.

## Supervision Architecture

These services run under s6 supervision:
- Each service runs in the foreground and outputs logs to standard error.
- Signal handling (TERM, INT, HUP) performs graceful hardware reset (turning off LEDs and buzzer, unmounting storage, removing FIFOs).
- In sixos, services are exposed declaratively via `reterminal-e1002/module.nix` and `nixosModules.reterminal-e1002`.
