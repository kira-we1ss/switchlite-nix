{
  description = "NixOS configuration for Nintendo Switch Lite (Mariko/T214) dual-boot";

  inputs = {
    # Pinned to 24.05 – pre-built aarch64 binaries available from cache.nixos.org
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs }:
  {
    # ---------------------------------------------------------------
    # The NixOS system for the Switch Lite.
    # Build it with:
    #   nix build .#nixosConfigurations.switch-lite.config.system.build.toplevel
    # ---------------------------------------------------------------
    nixosConfigurations.switch-lite = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";

      modules = [
        ./hardware-configuration.nix
        ./configuration.nix

        # Inject the L4T kernel package via overlay
        ({ pkgs, lib, ... }: {
          nixpkgs.overlays = [
            (final: prev: {
              switch-l4t-kernel = final.callPackage ./modules/l4t-kernel.nix {
                stdenv = final.gcc7Stdenv;
              };
              tegra-l4t-libs = final.callPackage ./modules/tegra-l4t.nix {
                inherit (final.xorg) libX11 libXext;
                inherit (final) libdrm;
              };
            })
          ];
        })
      ];
    };

    # ---------------------------------------------------------------
    # Convenience: build just the kernel package
    #   nix build .#packages.aarch64-linux.kernel
    # ---------------------------------------------------------------
    packages.aarch64-linux.kernel =
      let
        pkgs = import nixpkgs { system = "aarch64-linux"; };
      in
        pkgs.callPackage ./modules/l4t-kernel.nix {
          stdenv = pkgs.gcc7Stdenv;
        };
  };
}
