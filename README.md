# firecracker

Minimal Firecracker microVM sandbox for running static binaries in an isolated Linux VM.

## Prerequisites

- Linux x86_64 with KVM (`/dev/kvm`)
- Nix with flakes enabled

Load KVM if needed:
```bash
sudo modprobe kvm && sudo modprobe kvm_amd   # or kvm_intel
```

## Quick start

```bash
nix develop

# Build a rootfs with your static binary
bash build-rootfs.sh /path/to/my-static-binary

# Run it
bash fc-exec.sh my-static-binary --help
```

## Scripts

### `build-rootfs.sh`

Builds a 64MB ext4 rootfs with busybox and any extra static binaries you pass as arguments.

```bash
bash build-rootfs.sh                          # busybox only
bash build-rootfs.sh ./my-tool ./other-tool   # busybox + your binaries
```

Binaries are placed in `/usr/bin/` inside the guest. Requires `sudo` for `mount -o loop`.

### `fc-exec.sh`

Boot a VM, run a command, print the output, exit. ~0.9s overhead.

```bash
bash fc-exec.sh my-tool --version
bash fc-exec.sh sh -c "ls / && free -m && cat /proc/cpuinfo"
```

### `fc-run.sh`

Interactive VM with a shell on the serial console.

```bash
bash fc-run.sh                    # 1 vCPU, 4GB RAM
bash fc-run.sh --mem 8192         # 8GB RAM
bash fc-run.sh --cpus 4           # 4 vCPUs
bash fc-run.sh --net              # with internet access
bash fc-run.sh --net --mem 2048   # combine flags
```

Exit with Ctrl+C.

## What's inside the VM

- Linux 5.10.233 kernel (Firecracker CI build)
- Busybox (sh, ls, cat, mount, free, wget, etc.)
- Your static binaries
- No systemd, no distro, no package manager

## Networking

`--net` creates a TAP device on the host with NAT. The guest gets:

| | Address |
|---|---|
| Guest IP | 172.16.0.2 |
| Host/Gateway | 172.16.0.1 |
| DNS | 1.1.1.1 |

Requires `sudo` for TAP setup and iptables rules.

## Notes

- All guest binaries must be **statically linked** — there is no dynamic linker or libc in the rootfs
- Firecracker is pinned to v1.12.0
- The rootfs is copied before each boot (Firecracker modifies it), so changes inside the VM don't persist
- `fc-exec.sh` needs `sudo` for the `mount -o loop` to inject the init script
