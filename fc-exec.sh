#!/usr/bin/env bash
# Run a command in a fresh Firecracker VM and print the output.
# Usage: bash fc-exec.sh <command> [args...]
# Example: bash fc-exec.sh frozenkrill version
#          bash fc-exec.sh sh -c "ls / && free -m"
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command> [args...]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VMLINUX="${VMLINUX:?Set VMLINUX or run inside 'nix develop'}"
ROOTFS="$SCRIPT_DIR/rootfs.ext4"
CONFIG="/tmp/fc-exec-config.json"
CMD="$*"

if [ ! -f "$ROOTFS" ]; then
    echo "No rootfs.ext4 found. Run: bash build-rootfs.sh"
    exit 1
fi

cp "$ROOTFS" /tmp/fc-exec-rootfs.ext4

# Inject command into init
MNT="/tmp/fc-exec-mnt"
mkdir -p "$MNT"
sudo mount -o loop /tmp/fc-exec-rootfs.ext4 "$MNT"
sudo tee "$MNT/init" > /dev/null << INIT
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
export PATH=/usr/bin:/bin:/sbin
$CMD 2>&1
reboot -f
INIT
sudo chmod +x "$MNT/init"
sudo umount "$MNT"

cat > "$CONFIG" << EOF
{
  "boot-source": {
    "kernel_image_path": "$VMLINUX",
    "boot_args": "console=ttyS0 reboot=t panic=1 pci=off init=/init random.trust_cpu=on quiet"
  },
  "drives": [{
    "drive_id": "rootfs",
    "path_on_host": "/tmp/fc-exec-rootfs.ext4",
    "is_root_device": true,
    "is_read_only": false
  }],
  "machine-config": {
    "vcpu_count": 1,
    "mem_size_mib": 4096
  }
}
EOF

firecracker --no-api --config-file "$CONFIG" --log-path /dev/null 2>/dev/null | grep -v '^\['
