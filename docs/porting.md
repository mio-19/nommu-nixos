# E1002 firmware status

Fil-C is excluded. Userspace is conventional C/C++; correct programs are assumed. NOMMU has no per-process address-space isolation, so this does not protect other processes from a faulty pointer or stack exhaustion.

`nix run .#build-firmware -- .work` builds the pinned Xtensa FDPIC toolchain, then compiles skalibs, execline, s6, s6-rc, and s6-linux-init against the upstream NOMMU libc and fork compatibility library. It combines those with the sixos `mkConfiguration/s6-linux-init.nix` CPIO stage-one builder, compiles a small s6-rc database, verifies target ELF loaders and libraries, rebuilds the XIP cramfs image, checks partition limits, and merges the original upstream ESP32-S3 flash layout. No flash command is run.

The build deliberately keeps the known upstream 16MB map while the E1002 specifies 32MB. The kernel's MTD table and network adapter partition offsets must be changed together before using the additional flash. A merged binary that passes static checks is not proof that this board boots it.

`nix run .#test-emulator -- IMAGE.bin` runs the image under Espressif `esp-emu` 0.51.0 with an ESP32-S3 and 8MB PSRAM, then requires a Linux kernel banner on UART0. `esp-emu` does not provide the virtual access point and BLE stub the image's network adapter waits for, so it stops at `net80211 rom version` without loading Linux. Under `esp32sim` with `--wifi` and a `nimble_port_init` stub the image boots end to end: the kernel starts, the sixos CPIO stage one runs `rc.init`, `s6-rc-init` links the compiled database, the default bundle starts, and a Buildroot `login:` prompt appears on UART0. Neither emulator models the reTerminal peripherals, so the board work below is still untested.

Bring-up needed these target fixes, all applied by the build rather than by hand-editing upstream sources:

1. skalibs' selfpipe uses `signalfd`, which this kernel does not implement; the target build forces the pipe fallback (`--with-sysdep-signalfd=no`).
2. The kernel mounts devtmpfs on `/dev` itself, so sixos stage one must not pass `-d /dev` (`devtmpfs-mountpoint = null`), which previously failed with `Device or resource busy`.
3. `s6-svscan` reserves about 260 KiB of stack for its default 1000-service/251-byte-name tables, overflowing the 64 KiB NOMMU stack; it is wrapped with `-C 128 -L 64`.
4. The kernel rejects file-backed `mmap` with `ENODEV`, so skalibs' `cdb_init_fromfd` falls back to an anonymous mapping filled by `read()`.
5. An infinite relative `tain` deadline does not fit in 32-bit `time_t`; `pthread_mutex_tailock` treated that `EOVERFLOW` as a failure and broke every `s6-svlisten`/ftrigr subscription, so it now takes the blocking lock instead.
6. `s6-rc` executes oneshot `up` files as execline, so `early-setup` is invoked from a two-line execline wrapper instead of being stored as a shell script.
7. Runtime helpers `s6-ftrigrd`, `s6-svlisten`, `s6-svlisten1`, `s6-svwait`, and `s6-sudoc` are installed; without them `s6-rc-init` and oneshot activation fail with `ENOENT`.

Known emulator noise: `s6-linux-init-shutdownd` restarts repeatedly with `unable to read from pipe: Broken pipe` after boot. It does not affect service startup or the console, but shutdown handling on this target has not been validated.

The build adds the assembled target tree to the local Nix store with `nix store add` and copies that real content-addressed `/nix/store/<hash>-reterminal-sixos-system` object into the root cramfs. `/bin`, `/sbin`, and `/usr` are symlinks to paths within that object for compatibility with the upstream kernel and scripts. To fit the 7.5 MiB rootfs partition, the image omits upstream development tools including MicroPython, `make`, `nano`, `curl`, and `socat`. sixos' generated `rc.init` enters the system activation script, which initializes the compiled s6-rc database and starts its default runlevel. The minimal mount and UART services are generated with sixos' `mkOneshot`, `mkService`, and `mkBundle` constructors, then compiled with the host s6-rc compiler. This is not yet a full sixos `mkSite`/`mkConfiguration` evaluated system; the remaining step is supplying an Xtensa target package set and evaluating the complete site/configuration lifecycle. Network daemons are left disabled by default.

The E1002 schematic identifies GPIO3/4/5 as buttons, GPIO6 as the green LED, GPIO45 as buzzer enable, GPIO7/8/9 as display SPI, GPIO10/11/12/13 as display CS/DC/reset/busy, GPIO19/20 as I2C0 SDA/SCL, GPIO39/40 as I2C1, GPIO1 as battery ADC, and GPIO14/15/16 as the SD interface. The expansion header is GPIO46, GPIO2, GPIO17, GPIO18, GPIO20 and GPIO19. The current kernel tree has ESP32 GPIO, I2C and SPI support, but the board-specific panel, button, sensor, SD, charging and sleep integration still needs device-tree configuration and hardware testing. The earlier placeholder service scripts were removed.

Remaining board work:

1. Add an E1002 device tree and validate the board's flash chip, mode, PSRAM setup, UART0 console and 32MB partition table against its schematic.
2. Add real panel, button, I2C sensor, battery, SD and power-state drivers or userspace interfaces; avoid enabling services until they control hardware.
3. Integrate the complete sixos site configuration and lifecycle services, rather than the current small boot service graph.
4. Boot the exact image over serial, test shutdown/restart and JFFS2 persistence, then measure memory use under service load. There is no board attached to this build environment, so this hardware validation remains outstanding.
