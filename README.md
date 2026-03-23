# firecracker-sandbox

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
# Build a rootfs with your static binary
nix run github:douglaz/firecracker-sandbox -- build /path/to/my-static-binary

# Run it
nix run github:douglaz/firecracker-sandbox -- exec my-static-binary --help
```

## Commands

### `build`

Builds a 64MB ext4 rootfs with busybox and any extra static binaries.

```bash
nix run github:douglaz/firecracker-sandbox -- build                        # busybox only
nix run github:douglaz/firecracker-sandbox -- build ./my-tool ./other-tool # + your binaries
```

Binaries are placed in `/usr/bin/` inside the guest. Requires `sudo` for `mount -o loop`.

### `exec`

Boot a VM, run a command, print the output, exit. ~0.9s overhead.

```bash
nix run github:douglaz/firecracker-sandbox -- exec my-tool --version
nix run github:douglaz/firecracker-sandbox -- exec sh -c "ls / && free -m && cat /proc/cpuinfo"
```

### `run`

Interactive VM with a shell on the serial console.

```bash
nix run github:douglaz/firecracker-sandbox -- run                    # 1 vCPU, 4GB RAM
nix run github:douglaz/firecracker-sandbox -- run --mem 8192         # 8GB RAM
nix run github:douglaz/firecracker-sandbox -- run --cpus 4           # 4 vCPUs
nix run github:douglaz/firecracker-sandbox -- run --net              # with internet access
nix run github:douglaz/firecracker-sandbox -- run --net --mem 2048   # combine flags
```

Exit with Ctrl+C.

## Dev shell

```bash
cd ~/my-project
nix develop github:douglaz/firecracker-sandbox

firecracker-sandbox build ./my-binary
firecracker-sandbox exec my-binary --help
firecracker-sandbox run --net
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `FIRECRACKER_ROOTFS` | `./rootfs.ext4` | Path to the rootfs image |

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
- The rootfs is copied before each boot, so changes inside the VM don't persist
- `build` and `exec` require `sudo` for `mount -o loop`
