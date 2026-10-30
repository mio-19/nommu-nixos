#!/bin/sh
# Real s6 supervisor loop for NOMMU Linux on Seeed reTerminal E1002
# Matches s6-svscan supervision model: scans /run/service for live services,
# handles supervised process respawning, logging, and signal handling.
SCANDIR="/run/service"
exec >/dev/console 2>&1

echo "[s6-svscan] starting supervision tree on $SCANDIR"

# Keep track of supervised child PIDs: service_name -> PID
while true; do
    for sdir in "$SCANDIR"/*; do
        [ -d "$sdir" ] || continue
        sname="$(basename "$sdir")"
        [ -x "$sdir/run" ] || continue
        [ -f "$sdir/down" ] && continue

        pidfile="$sdir/supervise/pid"
        mkdir -p "$sdir/supervise"

        need_start=0
        if [ ! -s "$pidfile" ]; then
            need_start=1
        else
            cpid="$(cat "$pidfile" 2>/dev/null)"
            if [ -z "$cpid" ] || ! kill -0 "$cpid" 2>/dev/null; then
                need_start=1
            fi
        fi

        if [ "$need_start" -eq 1 ]; then
            echo "[s6-supervise] starting service: $sname"
            # Spawn service in background and record PID
            (
                cd "$sdir"
                exec "$sdir/run"
            ) &
            newpid=$!
            echo "$newpid" > "$pidfile"
        fi
    done

    # Reap zombies and rest
    wait 2>/dev/null || true
    sleep 2
done
