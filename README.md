# firecracker-sandbox

Run static Linux binaries in an isolated Firecracker microVM. Single command, nothing to install besides Nix.

## Prerequisites

- Linux x86_64 with KVM (`/dev/kvm`)
- Nix with flakes enabled

```bash
# Load KVM if needed
sudo modprobe kvm && sudo modprobe kvm_amd   # or kvm_intel
```

## Usage

```bash
# Run a command in a VM (builds a default rootfs automatically)
nix run github:douglaz/firecracker-sandbox -- exec uname -a

# Add your own static binary to the rootfs
nix run github:douglaz/firecracker-sandbox -- build /path/to/my-binary

# Run it
nix run github:douglaz/firecracker-sandbox -- exec my-binary --help

# Interactive shell
nix run github:douglaz/firecracker-sandbox -- run
```

### `build [binary...]`

Create a rootfs with busybox and optional extra static binaries.

```bash
nix run github:douglaz/firecracker-sandbox -- build                        # busybox only
nix run github:douglaz/firecracker-sandbox -- build ./my-tool ./other-tool # + your binaries
```

Binaries go to `/usr/bin/` in the guest. A default rootfs is built automatically on first `exec` or `run` if none exists.

### `exec [--net] [--mem MiB] [--cpus N] <cmd> [args...]`

Boot a VM, run a command, print the output, exit. ~0.9s overhead.

```bash
nix run github:douglaz/firecracker-sandbox -- exec my-tool --version
nix run github:douglaz/firecracker-sandbox -- exec sh -c "ls / && free -m"
nix run github:douglaz/firecracker-sandbox -- exec --net ping -c1 1.1.1.1
nix run github:douglaz/firecracker-sandbox -- exec --net wget -qO- http://ifconfig.me
nix run github:douglaz/firecracker-sandbox -- exec --mem 8192 --cpus 4 my-tool --benchmark
```

### `run [--net] [--mem MiB] [--cpus N]`

Interactive VM with a shell. Ctrl+C to exit.

```bash
nix run github:douglaz/firecracker-sandbox -- run
nix run github:douglaz/firecracker-sandbox -- run --net --mem 8192 --cpus 2
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--net` | off | Enable networking (TAP + NAT) |
| `--mem` | 4096 | Guest RAM in MiB |
| `--cpus` | 1 | Number of vCPUs |

## Networking

`--net` creates a TAP device with NAT to the host's default interface:

| | Address |
|---|---|
| Guest | 172.16.0.2 |
| Host/Gateway | 172.16.0.1 |
| DNS | 1.1.1.1 |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `FIRECRACKER_ROOTFS` | `./rootfs.ext4` | Path to the rootfs image |

## What's inside the VM

- Linux 5.10.233 kernel
- Busybox (sh, ls, cat, mount, free, wget, etc.)
- Your static binaries
- No systemd, no distro, no package manager

## Notes

- Guest binaries must be **statically linked**
- Firecracker v1.12.0 (pinned)
- Each boot uses a fresh copy of the rootfs — changes don't persist
- `build` and `exec` need `sudo` for `mount -o loop`
- `--net` needs `sudo` for TAP/iptables setup
