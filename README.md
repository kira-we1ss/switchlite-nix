# switch-nix

NixOS configuration for a Nintendo Switch Lite (Mariko / Tegra T214) running
alongside Atmosphère CFW as a dual-boot setup via hekate.

> **Status:** Work in progress. All source hashes are pinned. You can proceed
> directly to [Build NixOS](#4-build-nixos) after partitioning.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Switch Lite with mod chip | HWFLY, SX Core, etc. – RCM-only units cannot use hekate's Linux Flash tool |
| Atmosphère + hekate ≥ 6.0.6 | Already installed; Hekate manages the boot menu |
| microSD card ≥ 32 GB | 16 GB for NixOS root + space for Atmosphère |
| ThinkPad (x86_64) running NixOS | Used for cross-compilation |
| Nix ≥ 2.18 with flakes enabled | `nix.settings.experimental-features = ["nix-command" "flakes"]` |
| `binfmt` / QEMU aarch64 registered | Optional but speeds up interpreted builds |

---

## 1. Partition your SD card

> **WARNING:** This step wipes the SD card. Back everything up first (emuMMC,
> saves, Atmosphère files).

1. Boot your Switch into hekate.
2. Go to **Tools → Partition SD Card**.
3. Set up partitions roughly as follows (adjust sizes to your card):

   | Partition | Size | Filesystem | Purpose |
   |---|---|---|---|
   | p1 | ≥ 6 GB | FAT32 | Atmosphère, hekate, HOS backup |
   | p2 | ≥ 16 GB | ext4 | NixOS root |
   | p3 | 2–4 GB | linux-swap | Swap |

4. Tap **Flash Linux** – this writes the hekate Linux boot stub to the card.
5. Boot back to HorizonOS and run **Nyx Options → Dump Joy-Con BT** (required
   even on Switch Lite – it dumps factory touch/IMU calibration data).

Label the partitions when formatting them on your ThinkPad:

```bash
# Identify the card – DO NOT use the wrong device
lsblk
# Assuming /dev/sdX:
mkfs.fat  -F32 -n ATMOS  /dev/sdXp1
mkfs.ext4 -L   nixos     /dev/sdXp2
mkswap    -L   swap      /dev/sdXp3
```

---

## 2. Pinning sources

All 8 kernel source repos are already pinned to specific commit SHAs with
verified hashes in `modules/l4t-kernel.nix`. No manual prefetching is needed.

If you ever want to update to newer upstream commits, re-run:

```bash
nix run nixpkgs#nix-prefetch-github -- <owner> <repo> --rev <new-sha>
nix run nixpkgs#nix-prefetch-git -- <url> --rev refs/heads/<branch>
```

and replace the `rev` + `hash` fields in `modules/l4t-kernel.nix`.

---

## 3. Enable cross-compilation on your ThinkPad

Add to your ThinkPad's NixOS config:

```nix
# /etc/nixos/configuration.nix (ThinkPad)
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
nix.settings.extra-platforms = [ "aarch64-linux" ];
```

Then rebuild: `sudo nixos-rebuild switch`.

This registers QEMU binfmt handlers so Nix can run aarch64 binaries during
the build (needed for some configure scripts). Pure cross-compilation (no
QEMU) works for the kernel but some packages fall back to emulation.

---

## 4. Build NixOS

```bash
# From the repo directory on your ThinkPad:
nix build .#nixosConfigurations.switch-lite.config.system.build.toplevel \
  --system aarch64-linux
```

This will take a while the first time (it cross-compiles the entire closure).
Subsequent builds are cached.

To build just the kernel:

```bash
nix build .#kernel
```

---

## 5. Deploy to the SD card

Mount the NixOS ext4 partition:

```bash
sudo mount /dev/sdXp2 /mnt
sudo mkdir -p /mnt/boot
```

Copy the NixOS closure to the SD card using `nixos-install` or manually:

```bash
# The easiest way:
sudo nixos-install \
  --flake .#switch-lite \
  --root /mnt \
  --no-bootloader   # hekate is the bootloader; skip NixOS bootloader install
```

Copy the kernel and DTB to the FAT32 partition:

```bash
sudo mount /dev/sdXp1 /mnt/fat32
# uImage
sudo cp result/boot/uImage /mnt/fat32/uImage
# DTBs – hekate expects nx-plat.dtimg or individual DTBs
# Switch Lite (vali = HDH-001):
sudo cp result/boot/tegra210b01-vali.dtb /mnt/fat32/tegra210b01-vali.dtb
sudo umount /mnt/fat32
```

---

## 6. Add a hekate boot entry

Add the following to `hekate_ipl.ini` on the FAT32 partition:

```ini
[NixOS]
l=/uImage
r=/tegra210b01-vali.dtb
; Switch Lite (fric variant – try this if vali doesn't POST):
; r=/tegra210b01-fric.dtb
k=fbcon=map:0 video=1280x720@60 console=tty0 root=/dev/mmcblk0p2 rw rootwait quiet splash
icon=bootloader/res/icon_payload.bmp
```

Adjust the `root=` path if your NixOS partition is not `p2`.

Boot from hekate → **More Configs** → **NixOS**.

---

## Known limitations (Mariko / T214)

| Feature | Status |
|---|---|
| Display (internal 1280×720) | Works via tegra-fb / modesetting |
| Touch screen | Works (HID driver) |
| Joy-Con rails | Works (hid_nintendo) |
| Wi-Fi (BCM4354) | Works; may need nvs calibration file from HOS |
| Bluetooth | Partial (BCM4354 BT); pairing works, LE may be flaky |
| Audio (speakers + headphone) | Partial – ADSP firmware required |
| USB-C (data/charging) | USB host works; USB-PD negotiation untested |
| GPU acceleration (GNOME/Wayland) | Partial – Mesa tegra Gallium; no Vulkan |
| Suspend / resume | Not working in mainline L4T |
| HDMI dock output | Not applicable (Switch Lite has no dock connector) |

---

## Directory structure

```
switch-nix/
├── flake.nix                  # Flake entry point, cross-compilation setup
├── flake.lock                 # Pinned nixpkgs (generated by nix flake lock)
├── configuration.nix          # systemd + GNOME + SSH + networking
├── hardware-configuration.nix # Tegra T214 hardware, SD card layout
├── modules/
│   └── l4t-kernel.nix         # Custom L4T 4.9 kernel derivation
└── README.md                  # This file
```

---

## References

- [Switchroot wiki – L4T Ubuntu install guide](https://wiki.switchroot.org/wiki/linux/l4t-ubuntu-jammy-installation-guide)
- [theofficialgman/l4t-kernel-build-scripts](https://github.com/theofficialgman/l4t-kernel-build-scripts)
- [theofficialgman/switch-l4t-kernel-4.9](https://github.com/theofficialgman/switch-l4t-kernel-4.9)
- [Switchroot GitLab](https://gitlab.com/switchroot)
- [hekate releases](https://github.com/CTCaer/hekate/releases/latest)
