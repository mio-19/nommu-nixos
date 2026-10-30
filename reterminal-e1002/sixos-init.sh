#!/bin/sh
# s6 / sixos-style init script for nommu-nixos on Seeed reTerminal E1002
# Inspired by sixos (https://codeberg.org/amjoseph/sixos) stage 1 / s6-linux-init
set +e

echo "======================================================"
echo " Starting nommu-nixos with sixos-style init (s6-init) "
echo " Target: Seeed reTerminal E1002 (ESP32-S3 / Xtensa)   "
echo "======================================================"

# 1. Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs dev /dev

mkdir -p /dev/pts /dev/shm /run /tmp /var /var/log /var/run /run/service /run/boot
mount -t devpts devpts /dev/pts -o defaults,gid=5,mode=620,ptmxmode=0666
mount -t tmpfs tmpfs /dev/shm -o mode=0777
mount -t tmpfs tmpfs /run -o mode=0755,nosuid,nodev
mount -t tmpfs tmpfs /tmp -o mode=1777

# 2. Dump kernel boot arguments and environment
if [ -r /proc/cmdline ]; then
    cat /proc/cmdline > /run/boot/cmdline
fi

# 3. Mount MTD writable partitions if present (etc, home)
if [ -e /dev/mtdblock3 ] || grep -q 'mtd:etc' /proc/mtd 2>/dev/null; then
    mount -t jffs2 mtd:etc /etc 2>/dev/null || mount -t jffs2 /dev/mtdblock3 /etc 2>/dev/null || true
fi
if [ -e /dev/mtdblock5 ] || grep -q 'mtd:home' /proc/mtd 2>/dev/null; then
    mount -t jffs2 mtd:home /home 2>/dev/null || mount -t jffs2 /dev/mtdblock5 /home 2>/dev/null || true
fi

# 4. Generate/Restore basic system configuration if missing
[ -d /etc ] || mkdir -p /etc
[ -f /etc/hostname ] || echo "reterminal-e1002" > /etc/hostname
hostname -F /etc/hostname 2>/dev/null || hostname "reterminal-e1002"

# 5. Bring up loopback interface
ifconfig lo 127.0.0.1 up 2>/dev/null || ip addr add 127.0.0.1/8 dev lo 2>/dev/null || true

# 6. Unmute console / set printk if requested
if [ -f /etc/bootlog/verbose ]; then
    echo 8 > /proc/sys/kernel/printk 2>/dev/null
    dmesg
else
    echo 4 > /proc/sys/kernel/printk 2>/dev/null
fi

echo "Init system initialized successfully."
echo "Hardware: Seeed reTerminal E1002 (ESP32-S3, 32MB Flash, 8MB PSRAM)"
echo "Type 'exit' to restart shell."

# 7. Spawn console session (ttyS0 or ttyGS3 or fallback)
exec /bin/sh </dev/console >/dev/console 2>&1
