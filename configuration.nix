# Seeed reTerminal E1002 System Configuration
# NixOS / sixos on Linux NOMMU (ESP32-S3)
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./reterminal-e1002/module.nix
  ];

  # System Hostname
  networking.hostName = "reterminal-e1002";

  # Default Timezone
  time.timeZone = "UTC";

  # Hardware Platform Configuration
  hardware.reterminal = {
    enable = true;
    deviceTree.name = "esp32s3-reterminal-e1002.dtb";
  };

  # Supervised Peripheral Services (SenseCraft / TRMNL Parity)
  services.reterminal = {
    enable = true;
    buttons.enable = true;
    epaper.enable = true;
    sensors.enable = true;
    web = {
      enable = true;
      port = 8080;
    };
    sdcard.enable = true;
  };

  # Root User Configuration
  users.users.root = {
    home = "/home/root";
    shell = "/bin/sh";
  };

  # Packages to include in the system environment
  environment.systemPackages = [ ];

  # System State Version
  system.stateVersion = "26.11";
}
