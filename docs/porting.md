# E1002 firmware status

Fil-C is excluded. Userspace is conventional C/C++; correct programs are assumed. NOMMU has no per-process address-space isolation, so this does not protect other processes from a faulty pointer or stack exhaustion.

`nix run .#build-firmware -- .work` builds the pinned Xtensa FDPIC toolchain, then compiles skalibs, execline, s6, s6-rc, and s6-linux-init against the upstream NOMMU libc and fork compatibility library. It combines those with the sixos `mkConfiguration/s6-linux-init.nix` CPIO stage-one builder, compiles a small s6-rc database, verifies target ELF loaders and libraries, rebuilds the XIP cramfs image, checks partition limits, and merges the original upstream ESP32-S3 flash layout. No flash command is run.

The build deliberately keeps the known upstream 16MB map while the E1002 specifies 32MB. The kernel's MTD table and network adapter partition offsets must be changed together before using the additional flash. A merged binary that passes static checks is not proof that this board boots it.

`nix run .#test-emulator -- IMAGE.bin` runs the image under Espressif `esp-emu` 0.51.0 with an ESP32-S3 and 8MB PSRAM, then requires a Linux kernel banner on UART0. This emulator is useful for early boot debugging, but it does not model the reTerminal peripherals. The custom image reached ROM and early ESP-IDF output but timed out before a Linux banner. A local run of the unmodified upstream reference reached the ESP-IDF bootloader, then hit a task watchdog reset before Linux output; the Linux guest therefore remains unvalidated in emulation.

The build adds the assembled target tree to the local Nix store with `nix store add` and copies that real content-addressed `/nix/store/<hash>-reterminal-sixos-system` object into the root cramfs. `/bin`, `/sbin`, and `/usr` are symlinks to paths within that object for compatibility with the upstream kernel and scripts. To fit the 7.5 MiB rootfs partition, the image omits upstream development tools including MicroPython, `make`, `nano`, `curl`, and `socat`. sixos' generated `rc.init` enters the system activation script, which initializes the compiled s6-rc database and starts its default runlevel. The minimal mount and UART services are generated with sixos' `mkOneshot`, `mkService`, and `mkBundle` constructors, then compiled with the host s6-rc compiler. This is not yet a full sixos `mkSite`/`mkConfiguration` evaluated system; the remaining step is supplying an Xtensa target package set and evaluating the complete site/configuration lifecycle. Network daemons are left disabled by default.

The E1002 schematic identifies GPIO3/4/5 as buttons, GPIO6 as the green LED, GPIO45 as buzzer enable, GPIO7/8/9 as display SPI, GPIO10/11/12/13 as display CS/DC/reset/busy, GPIO19/20 as I2C0 SDA/SCL, GPIO39/40 as I2C1, GPIO1 as battery ADC, and GPIO14/15/16 as the SD interface. The expansion header is GPIO46, GPIO2, GPIO17, GPIO18, GPIO20 and GPIO19. The current kernel tree has ESP32 GPIO, I2C and SPI support, but the board-specific panel, button, sensor, SD, charging and sleep integration still needs device-tree configuration and hardware testing. The earlier placeholder service scripts were removed.

Remaining board work:

1. Add an E1002 device tree and validate the board's flash chip, mode, PSRAM setup, UART0 console and 32MB partition table against its schematic.
2. Add real panel, button, I2C sensor, battery, SD and power-state drivers or userspace interfaces; avoid enabling services until they control hardware.
3. Integrate the complete sixos site configuration and lifecycle services, rather than the current small boot service graph.
4. Boot the exact image over serial, test shutdown/restart and JFFS2 persistence, then measure memory use under service load. There is no board attached to this build environment, so this hardware validation remains outstanding.
