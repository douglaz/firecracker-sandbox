#!/usr/bin/env bash
# Build the guest rootfs with busybox + any extra static binaries.
# Usage: bash build-rootfs.sh [binary1 binary2 ...]
# Example: bash build-rootfs.sh /path/to/frozenkrill /path/to/my-tool
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOTFS="$SCRIPT_DIR/rootfs.ext4"
BUSYBOX="${BUSYBOX:?Set BUSYBOX or run inside 'nix develop'}"
MNT="/tmp/fc-build-mnt"

echo "Building rootfs..."

dd if=/dev/zero of="$ROOTFS" bs=1M count=64 status=none
mkfs.ext4 -F -q "$ROOTFS"

mkdir -p "$MNT"
sudo mount -o loop "$ROOTFS" "$MNT"

# Busybox + symlinks
sudo mkdir -p "$MNT"/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,tmp,etc,root}
sudo cp "$BUSYBOX" "$MNT/bin/busybox"
sudo chroot "$MNT" /bin/busybox --install -s 2>/dev/null || true

# Default init — interactive shell on serial
sudo tee "$MNT/init" > /dev/null << 'INIT'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts
export PATH=/usr/bin:/bin:/sbin
export HOME=/root
export TERM=vt100

# Network (if TAP device is configured)
if [ -e /sys/class/net/eth0 ]; then
    ip addr add 172.16.0.2/24 dev eth0
    ip link set eth0 up
    ip route add default via 172.16.0.1
    echo "nameserver 1.1.1.1" > /etc/resolv.conf
fi

exec setsid sh -c 'exec sh </dev/ttyS0 >/dev/ttyS0 2>&1'
INIT
sudo chmod +x "$MNT/init"

# Minimal /etc
echo "root:x:0:0:root:/root:/bin/sh" | sudo tee "$MNT/etc/passwd" > /dev/null

# Copy extra binaries
for bin in "$@"; do
    name="$(basename "$bin")"
    echo "  + /usr/bin/$name"
    sudo cp "$bin" "$MNT/usr/bin/$name"
    sudo chmod +x "$MNT/usr/bin/$name"
done

sudo umount "$MNT"
echo "Rootfs: $ROOTFS ($(du -h "$ROOTFS" | cut -f1))"
