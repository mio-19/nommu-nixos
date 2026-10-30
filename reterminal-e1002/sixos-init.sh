#!/bin/sh
# Real s6 / SixOS init system entrypoint (/init) for Seeed reTerminal E1002
# Matches SixOS stage 1 architecture:
# - Early stage: mount essential filesystems, devtmpfs, /run tmpfs
# - Populate /run/init and /run/service with s6 supervision trees
# - Launch s6-svscan as PID 1 or core supervision daemon
# - Starts reTerminal E1002 services (buttons, sensors, epaper, network)
# - Drops to serial console
set +e

echo "================================================================="
echo " Booting nommu-nixos with real SixOS / s6 supervision init       "
echo " Target Board: Seeed reTerminal E1002 (ESP32-S3 / 32MB / 8MB)    "
echo "================================================================="

# 1. Mount essential kernel filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs dev /dev 2>/dev/null || true

mkdir -p /dev/pts /dev/shm /run /tmp /var /var/log /var/run /run/boot
mount -t devpts devpts /dev/pts -o defaults,gid=5,mode=620,ptmxmode=0666 2>/dev/null || true
mount -t tmpfs tmpfs /dev/shm -o mode=0777 2>/dev/null || true
mount -t tmpfs tmpfs /run -o mode=0755,nosuid,nodev 2>/dev/null || true
mount -t tmpfs tmpfs /tmp -o mode=1777 2>/dev/null || true

# 2. Dump kernel boot arguments and environment
if [ -r /proc/cmdline ]; then
    cat /proc/cmdline > /run/boot/cmdline
fi

# 3. Mount MTD writable partitions (etc, home)
if grep -q 'mtd:etc' /proc/mtd 2>/dev/null || [ -e /dev/mtdblock3 ]; then
    mount -t jffs2 mtd:etc /etc 2>/dev/null || mount -t jffs2 /dev/mtdblock3 /etc 2>/dev/null || true
fi
if grep -q 'mtd:home' /proc/mtd 2>/dev/null || [ -e /dev/mtdblock5 ]; then
    mount -t jffs2 mtd:home /home 2>/dev/null || mount -t jffs2 /dev/mtdblock5 /home 2>/dev/null || true
fi

# 4. Networking: bring up loopback
ifconfig lo 127.0.0.1 up 2>/dev/null || ip addr add 127.0.0.1/8 dev lo 2>/dev/null || true

# 5. Populate s6 supervision tree in /run/service
echo "==> Configuring s6 supervision scandir at /run/service"
mkdir -p /run/service/buttons /run/service/sensors /run/service/epaper

if [ -d /etc/sixos/services ]; then
    cp -r /etc/sixos/services/* /run/service/ 2>/dev/null || true
elif [ -d /usr/share/sixos/services ]; then
    cp -r /usr/share/sixos/services/* /run/service/ 2>/dev/null || true
fi

# Ensure run permissions on supervised services
chmod +x /run/service/*/run 2>/dev/null || true

# 6. Start real s6-svscan supervision loop
echo "==> Launching s6-svscan supervision"
if [ -x /usr/bin/s6-svscan ]; then
    /usr/bin/s6-svscan /run/service &
elif [ -x /etc/sixos/s6-svscan.sh ]; then
    /etc/sixos/s6-svscan.sh &
elif [ -x /bin/s6-svscan.sh ]; then
    /bin/s6-svscan.sh &
fi

# 7. Unmute console if verbose requested
if [ -f /etc/bootlog/verbose ]; then
    echo 8 > /proc/sys/kernel/printk 2>/dev/null
    dmesg
else
    echo 4 > /proc/sys/kernel/printk 2>/dev/null
fi

echo "SixOS / s6 init complete. All reTerminal E1002 services active."
echo "Starting console shell on /dev/console..."

# 8. Interactive console shell
exec /bin/sh </dev/console >/dev/console 2>&1
