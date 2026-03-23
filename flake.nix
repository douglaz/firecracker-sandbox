{
  description = "Firecracker microVM sandbox for running static binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        firecracker = pkgs.stdenv.mkDerivation {
          pname = "firecracker";
          version = "1.12.0";
          src = pkgs.fetchurl {
            url = "https://github.com/firecracker-microvm/firecracker/releases/download/v1.12.0/firecracker-v1.12.0-x86_64.tgz";
            sha256 = "sha256-OStffkvxKHHR6Dd6YO07OEpGvC99N3HK8gKqemPjJnY=";
          };
          sourceRoot = ".";
          unpackPhase = "tar xzf $src";
          installPhase = ''
            mkdir -p $out/bin
            cp release-v1.12.0-x86_64/firecracker-v1.12.0-x86_64 $out/bin/firecracker
            chmod +x $out/bin/firecracker
          '';
        };

        vmlinux = pkgs.fetchurl {
          url = "https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.12/x86_64/vmlinux-5.10.233";
          sha256 = "sha256-OjDZHzv0deOVC5gl0EfGg5vGQknzg/YXORL+iv6JtcM=";
        };

        busybox = pkgs.pkgsStatic.busybox;

        firecracker-sandbox = pkgs.writeShellScriptBin "firecracker-sandbox" ''
          set -euo pipefail

          FC="${firecracker}/bin/firecracker"
          VMLINUX="${vmlinux}"
          BUSYBOX="${busybox}/bin/busybox"
          E2FSPROGS="${pkgs.e2fsprogs}"
          MKFS="$E2FSPROGS/bin/mkfs.ext4"
          ROOTFS="''${FIRECRACKER_ROOTFS:-./rootfs.ext4}"

          usage() {
            echo "Usage: firecracker-sandbox <command> [args...]"
            echo ""
            echo "Commands:"
            echo "  build [binary...]   Build rootfs with busybox + extra static binaries"
            echo "  exec [opts] <cmd>   Run a command in a fresh VM, print output, exit"
            echo "  run [--net] [--mem MiB] [--cpus N]   Interactive VM with shell"
            echo ""
            echo "Environment:"
            echo "  FIRECRACKER_ROOTFS  Path to rootfs.ext4 (default: ./rootfs.ext4)"
            echo ""
            echo "Examples:"
            echo "  firecracker-sandbox build /path/to/my-static-binary"
            echo "  firecracker-sandbox exec my-binary --help"
            echo "  firecracker-sandbox exec --net ping -c1 1.1.1.1"
            echo "  firecracker-sandbox exec sh -c 'ls / && free -m'"
            echo "  firecracker-sandbox run --net --mem 8192"
          }

          cmd_build() {
            echo "Building rootfs: $ROOTFS"
            dd if=/dev/zero of="$ROOTFS" bs=1M count=64 status=none
            "$MKFS" -F -q "$ROOTFS"

            MNT="$(mktemp -d)"
            sudo mount -o loop "$ROOTFS" "$MNT"
            trap 'sudo umount "$MNT" 2>/dev/null; rmdir "$MNT"' EXIT

            sudo mkdir -p "$MNT"/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,tmp,etc,root}
            sudo cp "$BUSYBOX" "$MNT/bin/busybox"
            sudo chroot "$MNT" /bin/busybox --install -s 2>/dev/null || true

            # Default init — interactive shell on serial with optional networking
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
          if [ -e /sys/class/net/eth0 ]; then
              ip addr add 172.16.0.2/24 dev eth0
              ip link set eth0 up
              ip route add default via 172.16.0.1
              echo "nameserver 1.1.1.1" > /etc/resolv.conf
          fi
          exec setsid sh -c 'exec sh </dev/ttyS0 >/dev/ttyS0 2>&1'
          INIT
            sudo chmod +x "$MNT/init"
            echo "root:x:0:0:root:/root:/bin/sh" | sudo tee "$MNT/etc/passwd" > /dev/null

            for bin in "$@"; do
              name="$(basename "$bin")"
              echo "  + /usr/bin/$name"
              sudo cp "$bin" "$MNT/usr/bin/$name"
              sudo chmod +x "$MNT/usr/bin/$name"
            done

            trap - EXIT
            sudo umount "$MNT"
            rmdir "$MNT"
            echo "Done: $ROOTFS ($(du -h "$ROOTFS" | cut -f1))"
          }

          # Shared: parse --net/--mem/--cpus flags, setup TAP+NAT if needed
          # Sets: MEM, CPUS, NET_CONFIG (globals)
          MEM=4096; CPUS=1; NET_CONFIG=""
          setup_opts() {
            local net=false
            while [ $# -gt 0 ]; do
              case "$1" in
                --net) net=true; shift ;;
                --mem) MEM="$2"; shift 2 ;;
                --cpus) CPUS="$2"; shift 2 ;;
                *) break ;;
              esac
            done
            # Return remaining args via global
            REMAINING_ARGS=("$@")

            if $net; then
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
              echo "Network: guest 172.16.0.2 <-> host 172.16.0.1 (NAT via $HOST_IFACE)" >&2
            fi
          }

          cmd_exec() {
            setup_opts "$@"; set -- "''${REMAINING_ARGS[@]}"
            if [ $# -eq 0 ]; then echo "Usage: firecracker-sandbox exec [--net] [--mem MiB] [--cpus N] <cmd> [args...]"; exit 1; fi
            if [ ! -f "$ROOTFS" ]; then cmd_build; fi

            TMPDIR="$(mktemp -d /tmp/fc-exec-XXXXXX)"
            trap 'rm -rf "$TMPDIR"' EXIT

            LIVE="$TMPDIR/rootfs.ext4"
            CONFIG="$TMPDIR/config.json"
            cp "$ROOTFS" "$LIVE"

            MNT="$TMPDIR/mnt"
            mkdir -p "$MNT"
            sudo mount -o loop "$LIVE" "$MNT"
            CMD="$*"
            NET_INIT=""
            if [ -n "$NET_CONFIG" ]; then
              NET_INIT='ip addr add 172.16.0.2/24 dev eth0; ip link set eth0 up; ip route add default via 172.16.0.1; echo "nameserver 1.1.1.1" > /etc/resolv.conf'
            fi
            sudo tee "$MNT/init" > /dev/null << INIT
          #!/bin/sh
          mount -t proc proc /proc
          mount -t sysfs sysfs /sys
          mount -t devtmpfs devtmpfs /dev 2>/dev/null
          export PATH=/usr/bin:/bin:/sbin
          $NET_INIT
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
            "drives": [{"drive_id":"rootfs","path_on_host":"$LIVE","is_root_device":true,"is_read_only":false}],
            "machine-config": {"vcpu_count":$CPUS,"mem_size_mib":$MEM}
            $NET_CONFIG
          }
          EOF
            "$FC" --no-api --config-file "$CONFIG" --log-path /dev/null 2>/dev/null | grep -v '^\['
          }

          cmd_run() {
            setup_opts "$@"; set -- "''${REMAINING_ARGS[@]}"
            if [ ! -f "$ROOTFS" ]; then cmd_build; fi

            TMPDIR="$(mktemp -d /tmp/fc-run-XXXXXX)"
            trap 'rm -rf "$TMPDIR"' EXIT

            LIVE="$TMPDIR/rootfs.ext4"
            CONFIG="$TMPDIR/config.json"
            cp "$ROOTFS" "$LIVE"

            cat > "$CONFIG" << EOF
          {
            "boot-source": {
              "kernel_image_path": "$VMLINUX",
              "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/init random.trust_cpu=on"
            },
            "drives": [{"drive_id":"rootfs","path_on_host":"$LIVE","is_root_device":true,"is_read_only":false}],
            "machine-config": {"vcpu_count":$CPUS,"mem_size_mib":$MEM}
            $NET_CONFIG
          }
          EOF
            echo "Firecracker VM: ''${CPUS} vCPU, ''${MEM}MB RAM (Ctrl+C to exit)"
            "$FC" --no-api --config-file "$CONFIG" --log-path /dev/null
          }

          case "''${1:-}" in
            build) shift; cmd_build "$@" ;;
            exec)  shift; cmd_exec "$@" ;;
            run)   shift; cmd_run "$@" ;;
            *)     usage ;;
          esac
        '';
      in
      {
        packages.default = firecracker-sandbox;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            firecracker-sandbox
            firecracker
            pkgs.e2fsprogs
          ];

          VMLINUX = "${vmlinux}";
          BUSYBOX = "${busybox}/bin/busybox";

          shellHook = ''
            echo "=== Firecracker sandbox ==="
            echo ""
            echo "  firecracker-sandbox build [binaries...]"
            echo "  firecracker-sandbox exec <cmd> [args...]"
            echo "  firecracker-sandbox run [--net] [--mem MiB] [--cpus N]"
          '';
        };
      });
}
