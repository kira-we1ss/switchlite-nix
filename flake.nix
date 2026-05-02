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
      # Target architecture
      system = "aarch64-linux";

      modules = [
        # Tell NixOS to cross-compile from x86_64 (your ThinkPad)
        { nixpkgs.buildPlatform.system = "x86_64-linux"; }

        ./hardware-configuration.nix
        ./configuration.nix

        # Inject the L4T kernel package via overlay
        ({ pkgs, lib, ... }: {
          nixpkgs.overlays = [
            (final: prev: {
              switch-l4t-kernel = final.callPackage ./modules/l4t-kernel.nix {};
            })
          ];
        })
      ];
    };

    # ---------------------------------------------------------------
    # Convenience: build just the kernel package
    #   nix build .#packages.x86_64-linux.kernel
    # ---------------------------------------------------------------
    packages.x86_64-linux.kernel =
      let
        pkgsCross = import nixpkgs {
          system      = "x86_64-linux";
          crossSystem = { config = "aarch64-unknown-linux-gnu"; };
        };
      in
        pkgsCross.callPackage ./modules/l4t-kernel.nix {};
  };
}
