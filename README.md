# nommu-nixos

Nix build workspace for a sixos configuration on ESP32-S3 Linux. Userspace is conventional C/C++; Fil-C is excluded and correct programs are assumed.

The configuration evaluates the pinned sixos **site → host → mkConfiguration** lifecycle. Sixos assigns service names, resolves dependencies, generates users/groups and target actions, and compiles the s6-rc database. An ESP32 platform adapter supplies Xtensa binaries built with the upstream SDK and packages an immutable flash image. The image retains the upstream devkit's 16MB flash layout; reTerminal E1002 peripherals and its 32MB flash layout still need hardware bring-up.

```sh
nix build                         # porting kit and pinned source manifest
nix build .#upstream-reference    # upstream 16MB devkit reference
nix flake check                  # partition tests and sixos init archive
nix fmt                          # format Nix sources
nix develop                      # host tools and source paths
nix run .#build-firmware -- .work # SDK, target packages, sixos site, image
```

The full build uses rootless Podman for the pinned upstream SDK bootstrap. It cross-compiles skalibs, execline, s6, s6-rc, s6-linux-init and s6-portable-utils, snapshots those build outputs into the Nix store, then builds the configuration through `lib.mkSixosSite`. The s6-rc compiler runs natively under Nix and uses the target configuration headers to embed target executable paths.

The image is written to `.work/firmware/reterminal-e1002-six-init-experimental.bin`. Existing firmware output directories are refused; preserve or rename an earlier output before rebuilding. The assembler copies the configuration's actual Nix runtime closure, sets `/nix/var/nix/profiles/system`, and keeps `/bin`, `/usr` and `/lib` as compatibility links into the target userspace package. `/sbin/init` unpacks sixos' stage-one archive and starts the supervised system.

The default bundle contains filesystem setup, UART login, and clock restore/save services. `/run/current-system`, `/run/booted-system`, `/run/target` and `six/s6-rc/{source,db}` follow sixos conventions. Repeat activation reasserts the default bundle without replacing live service directories. Deployment happens on the host by replacing the flash image: on-device Nix, doas deployment and kexec helpers are omitted for the immutable 8 MiB PSRAM target. This is a complete evaluated board configuration with a firmware-specific deployment adapter, rather than a general nixpkgs Xtensa cross-platform port.

To repeat the end-to-end test with `esp32sim` 0.3.0 and an ESP32-S3 ROM ELF:

```sh
ESP32SIM=/path/to/esp32sim ESP32SIM_ROM=/path/to/esp32s3_rev0_rom.elf \
  tools/test-sixos.sh .work/firmware/reterminal-e1002-six-init-experimental.bin
```

The test uses a virtual AP and a BLE provisioning stub specific to the pinned network adapter. It requires Linux, sixos init, exactly one successful start of every board service, and a UART login prompt. Defaults use `.work/esp32sim/esp32sim` and `.work/esp32sim-roms/esp32s3_rev0_rom.elf` when already installed. Set `SIXOS_TEST_LIFECYCLE=1` to also test root login, repeat activation, clock saving and software reboot in a disposable emulator run.

The older `nix run .#test-emulator` path uses Espressif's `esp-emu`; it stalls before Linux for this image and does not validate sixos.

The firmware remains untested on E1002 hardware. It does not yet drive its ePaper panel, sensors, buttons, battery management or sleep mode. NOMMU does not isolate process memory. See [porting notes](docs/porting.md) for platform adaptations and remaining board work.

Sources: [Linux-on-esp32-S3](https://github.com/paulneja/Linux-on-esp32-S3), [sixos](https://codeberg.org/amjoseph/sixos), [reTerminal E1002 schematic](https://files.seeedstudio.com/wiki/reterminal_e10xx/res/202004321_reTerminal_E1002_V1_2_SCH_251120.pdf), [Seeed E1002 guide](https://wiki.seeedstudio.com/getting_started_with_reterminal_e1002/).
