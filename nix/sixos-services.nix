# Build the firmware's minimal boot graph with sixos' own service constructors.
{
  pkgs,
  sixos-src,
  early-setup,
  console-run,
}:
let
  lib = pkgs.lib;
  targetPackage = {
    outPath = "/usr";
  };
  targetPkgs = pkgs // {
    s6 = targetPackage;
    s6-rc = targetPackage;
  };
  six = rec {
    util = {
      infuse = old: new: old // new;
      execline = rec {
        isArg = arg: lib.isPath arg || lib.isString arg || lib.isDerivation arg;
        isArgv = argv: lib.isList argv && lib.all isArg argv;
        isExecline = arg: isArg arg || (lib.isList arg && lib.all isExecline arg);
        assertIsExecline =
          arg: if isExecline arg then true else throw "sixos service action must be an execline expression";
      };
    };
    mkService =
      args:
      import "${sixos-src}/mkConfiguration/mkService.nix" (
        {
          inherit lib six;
          pkgs = targetPkgs;
        }
        // args
      );
    mkOneshot =
      args: import "${sixos-src}/mkConfiguration/mkOneshot.nix" ({ inherit lib six; } // args);
    mkBundle = args: import "${sixos-src}/mkConfiguration/mkBundle.nix" ({ inherit lib six; } // args);
  };
  early = six.mkOneshot {
    up = builtins.readFile early-setup;
    passthru.spath = [ "early-setup" ];
  };
  console = six.mkService {
    type = "longrun";
    up = builtins.readFile console-run;
    extraCommands = "cp $out/up $out/run";
    passthru = {
      spath = [ "console" ];
      after = [ early ];
    };
  };
  default = six.mkBundle {
    passthru = {
      spath = [ "default" ];
      after = [
        console
        early
      ];
    };
  };
  services = [
    early
    console
    default
  ];
in
pkgs.runCommand "sixos-reterminal-service-source" { } ''
  mkdir -p $out
  ${lib.concatMapStrings (service: ''
    mkdir -p $out/${lib.concatStringsSep "." service.passthru.spath}
    cp -a ${service}/. $out/${lib.concatStringsSep "." service.passthru.spath}/
  '') services}
''
