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

        # Pin Firecracker v1.12.0 binary
        firecracker = pkgs.stdenv.mkDerivation {
          pname = "firecracker";
          version = "1.12.0";
          src = pkgs.fetchurl {
            url = "https://github.com/firecracker-microvm/firecracker/releases/download/v1.12.0/firecracker-v1.12.0-x86_64.tgz";
            sha256 = "sha256-NwCmDPKJqpMaGpg/WpCusFCp3kT4dOJoGaUzRl2mz1s=";
          };
          sourceRoot = ".";
          unpackPhase = "tar xzf $src";
          installPhase = ''
            mkdir -p $out/bin
            cp release-v1.12.0-x86_64/firecracker-v1.12.0-x86_64 $out/bin/firecracker
            chmod +x $out/bin/firecracker
          '';
        };

        # Fetch Firecracker-compatible kernel
        vmlinux = pkgs.fetchurl {
          url = "https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.12/x86_64/vmlinux-5.10.233";
          sha256 = "sha256-UMFBfxKfOoclrMnLqOKOFSMNjGMOELSJiJYBd5RA/YQ=";
        };

        # Static busybox for the guest rootfs
        busybox = pkgs.pkgsStatic.busybox;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            firecracker
            pkgs.e2fsprogs
            pkgs.curl
          ];

          VMLINUX = "${vmlinux}";
          BUSYBOX = "${busybox}/bin/busybox";

          shellHook = ''
            echo "=== Firecracker sandbox ==="
            echo ""
            echo "Build rootfs:     bash build-rootfs.sh [extra binaries...]"
            echo "Interactive:      bash fc-run.sh"
            echo "Run a command:    bash fc-exec.sh <cmd> [args...]"
          '';
        };
      });
}
