#!/usr/bin/env bash
# Interactive Firecracker VM. Gives you a shell over serial.
# Usage: bash fc-run.sh [--net] [--mem MiB] [--cpus N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VMLINUX="${VMLINUX:?Set VMLINUX or run inside 'nix develop'}"
ROOTFS="$SCRIPT_DIR/rootfs.ext4"
CONFIG="/tmp/fc-run-config.json"
MEM=4096
CPUS=1
NET=false
HOST_IFACE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --net) NET=true; shift ;;
        --mem) MEM="$2"; shift 2 ;;
        --cpus) CPUS="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ ! -f "$ROOTFS" ]; then
    echo "No rootfs.ext4 found. Run: bash build-rootfs.sh"
    exit 1
fi

cp "$ROOTFS" /tmp/fc-run-rootfs.ext4

# Network setup
NET_CONFIG=""
if $NET; then
    TAP="fc-tap0"
    HOST_IFACE="$(ip route | awk '/^default/{print $5; exit}')"

    if ! ip link show "$TAP" &>/dev/null; then
        sudo ip tuntap add dev "$TAP" mode tap user "$(id -u)"
        sudo ip addr add 172.16.0.1/24 dev "$TAP"
        sudo ip link set "$TAP" up
        sudo sysctl -q net.ipv4.ip_forward=1
        sudo iptables -t nat -C POSTROUTING -o "$HOST_IFACE" -s 172.16.0.0/24 -j MASQUERADE 2>/dev/null \
            || sudo iptables -t nat -A POSTROUTING -o "$HOST_IFACE" -s 172.16.0.0/24 -j MASQUERADE
        sudo iptables -C FORWARD -i "$TAP" -o "$HOST_IFACE" -j ACCEPT 2>/dev/null \
            || sudo iptables -A FORWARD -i "$TAP" -o "$HOST_IFACE" -j ACCEPT
        sudo iptables -C FORWARD -i "$HOST_IFACE" -o "$TAP" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
            || sudo iptables -A FORWARD -i "$HOST_IFACE" -o "$TAP" -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi

    NET_CONFIG=',"network-interfaces":[{"iface_id":"eth0","guest_mac":"AA:FC:00:00:00:01","host_dev_name":"'$TAP'"}]'
    echo "Network: guest 172.16.0.2 <-> host 172.16.0.1 (NAT via $HOST_IFACE)"
fi

cat > "$CONFIG" << EOF
{
  "boot-source": {
    "kernel_image_path": "$VMLINUX",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/init random.trust_cpu=on"
  },
  "drives": [{
    "drive_id": "rootfs",
    "path_on_host": "/tmp/fc-run-rootfs.ext4",
    "is_root_device": true,
    "is_read_only": false
  }],
  "machine-config": {
    "vcpu_count": $CPUS,
    "mem_size_mib": $MEM
  }
  $NET_CONFIG
}
EOF

echo "Firecracker VM: ${CPUS} vCPU, ${MEM}MB RAM (Ctrl+C to exit)"
exec firecracker --no-api --config-file "$CONFIG" --log-path /dev/null
