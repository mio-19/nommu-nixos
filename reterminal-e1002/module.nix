# NixOS module for Seeed reTerminal E1002 (ESP32-S3 NOMMU)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.reterminal-e1002;
in
{
  options = {
    hardware.reterminal-e1002 = {
      enable = lib.mkEnableOption "Seeed reTerminal E1002 hardware platform support";

      deviceTree = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "esp32s3-reterminal-e1002.dtb";
          description = "Name of the compiled device tree blob.";
        };

        source = lib.mkOption {
          type = lib.types.path;
          default = ./esp32s3-reterminal-e1002.dts;
          description = "Device Tree Source file for reTerminal E1002.";
        };
      };
    };

    hardware.deviceTree = {
      enable = lib.mkEnableOption "Device Tree support";

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Default DTB file to load.";
      };
    };

    boot.loader.esp-idf = {
      enable = lib.mkEnableOption "ESP-IDF bootloader configuration";

      chip = lib.mkOption {
        type = lib.types.str;
        default = "esp32s3";
        description = "Target ESP32 microcontroller SoC.";
      };

      flashSize = lib.mkOption {
        type = lib.types.str;
        default = "32MB";
        description = "SPI flash size.";
      };

      flashMode = lib.mkOption {
        type = lib.types.enum [
          "dio"
          "qio"
          "dout"
          "qout"
          "opi"
          "qpi"
        ];
        default = "dio";
        description = "SPI flash mode.";
      };

      flashFreq = lib.mkOption {
        type = lib.types.enum [
          "40m"
          "80m"
          "120m"
        ];
        default = "80m";
        description = "SPI flash frequency.";
      };

      partitionTable = lib.mkOption {
        type = lib.types.path;
        default = ./partitions_32mb.csv;
        description = "ESP-IDF partition table CSV.";
      };
    };

    services.reterminal = {
      enable = lib.mkEnableOption "reTerminal E1002 peripheral supervision services";

      buttons = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable GPIO buttons (3, 4, 5), status LED (6), and buzzer (45) service.";
        };
      };

      epaper = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable 7.3-inch Spectra 6 ED2208 ePaper driver daemon on SPI2.";
        };
      };

      sensors = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable SHT40, PCF8563 RTC, and battery ADC telemetry polling service.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.deviceTree = {
      enable = lib.mkDefault true;
      name = lib.mkDefault cfg.deviceTree.name;
    };
    boot.loader.esp-idf.enable = lib.mkDefault true;
    services.reterminal.enable = lib.mkDefault true;
  };
}
