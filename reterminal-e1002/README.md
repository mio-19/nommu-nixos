# Seeed reTerminal E1002 Hardware Support

Target: **Seeed reTerminal E1002**
SoC: **Espressif ESP32-S3 (ESP32-S3-WROOM-1-N32R8)**
Flash: **32MB Octal SPI Flash**
PSRAM: **8MB Octal PSRAM**

## Pinout Map

| Function | Pin / GPIO | Description |
|---|---|---|
| Console TX | GPIO43 | UART0 TXD (115200 baud) |
| Console RX | GPIO44 | UART0 RXD |
| Left Button | GPIO3 | Active Low, internal pull-up |
| Middle Button | GPIO4 | Active Low, internal pull-up |
| Right Button | GPIO5 | Active Low, internal pull-up |
| Status LED | GPIO6 | Green LED, Active Low |
| Buzzer Enable | GPIO45 | Active High |
| Battery Voltage | GPIO1 | ADC1 CH0 (voltage divider) |
| I2C0 SDA | GPIO19 | SHT40 (0x44) & PCF8563 (0x51) |
| I2C0 SCL | GPIO20 | I2C Bus Clock |
| I2C1 SDA | GPIO39 | Secondary / expansion I2C |
| I2C1 SCL | GPIO40 | Secondary / expansion I2C |
| ePaper SCK | GPIO7 | SPI2 SCK |
| ePaper MOSI | GPIO9 | SPI2 MOSI |
| ePaper CS | GPIO10 | SPI2 CS0 |
| ePaper DC | GPIO11 | Data / Command select |
| ePaper Reset | GPIO12 | Panel reset |
| ePaper Busy | GPIO13 | Busy status indicator |
| SD CLK | GPIO14 | SPI3 / SDMMC CLK |
| SD CMD | GPIO15 | SPI3 MOSI / SDMMC CMD |
| SD DAT0 | GPIO16 | SPI3 MISO / SDMMC DAT0 |
| SD CS | GPIO21 | SPI3 Chip Select |

## Flash Memory Layout (32MB)

See [`partitions_32mb.csv`](file:///home/dev/Documents/nommu-nixos/reterminal-e1002/partitions_32mb.csv):

- `0x00000000` - `0x00008000`: Bootloader (32 KiB)
- `0x00008000` - `0x00009000`: Partition Table (4 KiB)
- `0x0000a000` - `0x0000f000`: NVS partition (20 KiB)
- `0x0000f000` - `0x00010000`: PHY calibration (4 KiB)
- `0x00010000` - `0x000d0000`: ESP-IDF Network Adapter (768 KiB)
- `0x000d0000` - `0x00140000`: `/etc` JFFS2 partition (448 KiB)
- `0x00140000` - `0x00540000`: Linux Kernel XIP (4 MiB)
- `0x00540000` - `0x01a40000`: Root filesystem CramFS (21 MiB)
- `0x01a40000` - `0x01fc0000`: `/home` JFFS2 partition (5.5 MiB)

## Device Tree

[`esp32s3-reterminal-e1002.dts`](file:///home/dev/Documents/nommu-nixos/reterminal-e1002/esp32s3-reterminal-e1002.dts) defines the memory layout, 32MB flash node, pin controllers, I2C devices, SPI displays, and input buttons matching the v1.2 schematic.

## Flashing to Hardware

To flash an image to the Seeed reTerminal E1002:

```sh
# Connect reTerminal E1002 via USB-C (ensure boot mode: hold boot button while resetting if necessary)
esptool --chip esp32s3 -p /dev/ttyACM0 -b 460800 write_flash \
  --flash-mode dio --flash-size 32MB --flash-freq 80m \
  0x0 firmware-image.bin
```
