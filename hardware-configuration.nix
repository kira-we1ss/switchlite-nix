# Hardware configuration for Nintendo Switch Lite (Mariko, Tegra T214 / tegra210b01)
#
# SD card partition layout assumed (created via hekate → Tools → Partition SD Card):
#
#   /dev/mmcblk0p1  FAT32     ≥ 6 GB    Atmosphère + hekate boot files (shared)
#   /dev/mmcblk0p2  ext4      ≥ 16 GB   NixOS root
#   /dev/mmcblk0p3  linux-swap ≥ 2 GB   optional swap
#
# The exact device path on the Switch is /dev/mmcblk0 for the microSD card.
# eMMC (internal NAND) is /dev/mmcblk1 and should NOT be touched.
#
# If hekate partitioned your card differently, adjust the partition numbers
# (p1/p2/p3) and sizes below to match.  Use `lsblk` or `blkid` in a live
# environment to confirm.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # ---------------------------------------------------------------
  # Block device identifiers
  # Using partition labels is more robust than device paths across
  # reboots or kernel updates.  Set the labels when formatting:
  #   mkfs.fat  -F32 -n ATMOS   /dev/mmcblk0p1
  #   mkfs.ext4 -L   nixos      /dev/mmcblk0p2
  #   mkswap    -L   swap       /dev/mmcblk0p3
  # ---------------------------------------------------------------
  fileSystems."/" = {
    device  = "/dev/disk/by-label/nixos";
    fsType  = "ext4";
    options = [
      "noatime"       # reduce write amplification on SD card
      "nodiratime"
      "errors=remount-ro"
    ];
  };

  # Mount the FAT32 boot partition read-only so NixOS can read
  # hekate config files if needed, but cannot accidentally corrupt
  # the Atmosphère installation.
  fileSystems."/boot/switch" = {
    device  = "/dev/disk/by-label/ATMOS";
    fsType  = "vfat";
    options = [ "ro" "umask=0077" "nofail" ];
  };

  swapDevices = [{
    device = "/dev/disk/by-label/swap";
  }];

  # ---------------------------------------------------------------
  # CPU / SoC
  # ---------------------------------------------------------------
  # Tegra T214 (codename "Mariko") has 4× Cortex-A57 cores.
  # We do NOT set cpuFreqGovernor here because that pulls in cpupower,
  # which fails to compile against newer binutils with the 4.9 kernel.
  # The kernel's built-in schedutil governor is used instead.

  # ---------------------------------------------------------------
  # Hardware modules that must be loaded early
  # ---------------------------------------------------------------
  boot.initrd.kernelModules = [
    # eMMC / SD controller
    "sdhci_tegra"
    # Framebuffer (needed for early console output)
    "tegra-dc"
    # USB (xHCI for the USB-C port on Switch Lite)
    "xhci_tegra"
  ];

  boot.kernelModules = [
    # Wi-Fi: BCM4354 on Switch Lite (Mariko)
    "brcmfmac"
    # Bluetooth: BCM4354 BT (shared chip)
    "btbcm"
    "hci_uart"
    # Joy-Con / Pro Controller HID driver
    "hid_nintendo"
    # GPU
    "nvgpu"
    # ALSA/ASoC Tegra audio
    "snd_soc_tegra_rt5639"
    "snd_soc_tegra210_admaif"
  ];

  # ---------------------------------------------------------------
  # DRM / display
  # ---------------------------------------------------------------
  # The L4T kernel exposes the internal display via /dev/fb0 (tegra-fb)
  # and a DRM node.  We use the modesetting Xorg driver backed by that.
  hardware.opengl = {
    enable          = true;
    driSupport      = true;
    # Tegra's Mesa driver is "tegra" (Nouveau-based upstream) or the
    # NVIDIA proprietary Tegra driver.  The L4T kernel works best with
    # the upstream tegra Gallium driver available in Mesa ≥ 23.x.
    extraPackages   = with pkgs; [ mesa ];
  };

  # ---------------------------------------------------------------
  # Platform – declared in flake.nix via nixpkgs.buildPlatform
  # ---------------------------------------------------------------
}
