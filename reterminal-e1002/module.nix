# NixOS / sixos module for Seeed reTerminal E1002
{
  config,
  lib,
  pkgs,
  ...
}:
{
  hardware.deviceTree = {
    name = "esp32s3-reterminal-e1002.dtb";
    source = ./esp32s3-reterminal-e1002.dts;
  };

  boot.loader.esp-idf = {
    chip = "esp32s3";
    flashSize = "32MB";
    flashMode = "dio";
    flashFreq = "80m";
    partitionTable = ./partitions_32mb.csv;
  };

  # reTerminal E1002 hardware peripheral services
  services.reterminal = {
    enable = lib.mkDefault true;
    buttons.enable = lib.mkDefault true;
    epaper.enable = lib.mkDefault true;
    sensors.enable = lib.mkDefault true;
  };
}
