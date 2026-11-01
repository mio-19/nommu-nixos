# s6-svscan Peripheral Scandir Configuration

In s6 supervision architecture, `s6-svscan` monitors a scan directory (such as `/run/service`) where each subdirectory represents a supervised service with its `run` script.

To activate reTerminal E1002 peripheral supervision on the target:
```sh
mkdir -p /run/service
cp -a /etc/sixos/services/reterminal/* /run/service/
s6-svscanctl -a /run/service
```
Or include them in the sixos site target definition (`nix/sixos-site.nix`).
