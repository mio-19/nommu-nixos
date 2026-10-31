# Entry point used after tools/build-skarnet.sh has built the target SDK packages.
{
  repo,
  stack,
  system ? builtins.currentSystem,
}:
let
  flake = builtins.getFlake (
    (if builtins.pathExists (repo + "/.git") then "git+file://" else "path:") + repo
  );
in
(flake.lib.mkSixosSite {
  inherit system;
  stack = builtins.storePath stack;
}).configuration
