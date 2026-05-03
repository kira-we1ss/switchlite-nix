# switch-nix

NixOS configuration for a Nintendo Switch Lite (Mariko / Tegra T214) running
alongside Atmosphère CFW as a dual-boot setup via hekate.

> **Status:** Work in progress. All source hashes are pinned. CI builds and
> publishes releases automatically on every push to `main`.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Switch Lite with mod chip | HWFLY, SX Core, etc. – RCM-only units cannot use hekate |
| Atmosphère + hekate ≥ 6.0.6 | Already installed; hekate manages the boot menu |
| microSD card ≥ 32 GB | Recommended: 128 GB U3/A2 class |
| Switchroot L4T Ubuntu installed | Required for the bootstack (`bl31.bin`, `bl33.bin`, U-Boot etc.) |

> **This NixOS build relies on the Switchroot L4T Ubuntu bootstack.**
> You must install L4T Ubuntu first (even briefly), which deploys the firmware files hekate needs to boot any Linux distro.
> After that you replace the kernel and rootfs with ours.

---

## 1. Install the Switchroot L4T Ubuntu bootstack

1. Download the latest [L4T Ubuntu Jammy image](https://download.switchroot.org/ubuntu-jammy/)
2. Extract the 7z to the root of your FAT32 SD card partition
3. In hekate go to **Tools → Partition SD Card → Flash Linux** — this installs `bl31.bin`, `bl33.bin`, BPMP firmware etc. into `bootloader/sys/l4t/`
4. Run **Nyx Options → Dump Joy-Con BT** (required even on Switch Lite — dumps factory touch/IMU calibration)

At this point L4T Ubuntu should boot. You can verify it works before proceeding.

---

## 2. Partition your SD card

You need at least:

| Partition | Filesystem | Purpose |
|---|---|---|
| p1 | FAT32 | Atmosphère, hekate, L4T bootstack (already set up by step 1) |
| p2 | ext4 | NixOS root |
| p3 | linux-swap (optional) | Swap |

If hekate's partition manager doesn't create the ext4/swap partitions, create them on your PC:

```bash
# Assuming the FAT32 partition already exists as p1
parted /dev/sdX mkpart primary ext4 Xgib Ygib
parted /dev/sdX mkpart primary linux-swap Ygib 100%
mkfs.ext4 -L nixos /dev/sdXp2
mkswap -L swap /dev/sdXp3
```

---

## 3. Get the NixOS build artifacts

Download the latest release assets from the [Releases page](../../releases/latest):

| File | Purpose |
|---|---|
| `Image` | Kernel image – replaces the L4T Ubuntu kernel |
| `tegra210b01-vali.dtb` | DTB for Switch Lite (HDH-001, try this first) |
| `tegra210b01-fric.dtb` | DTB for Switch Lite (fric fuse variant) |
| `nixos-rootfs.tar.zst` / `.tar.zst.part*` | Full NixOS root closure – may be split into chunks |
| `hekate_ipl.ini.snippet` | Add to `hekate_ipl.ini` on the FAT32 partition |

---

## 4. Deploy to the SD card

Run all commands on your PC with the SD card mounted:

```bash
sudo mount /dev/sdXp1 /mnt/fat32
sudo mount /dev/sdXp2 /mnt/nixos

# Replace the L4T Ubuntu kernel with ours
sudo cp Image /mnt/fat32/switchroot/ubuntu/Image

# NixOS rootfs – if split into .part* chunks (likely), reassemble and extract:
cat nixos-rootfs.tar.zst.part* | sudo tar --zstd -xf - -C /mnt/nixos --numeric-owner
# If a single file:
# sudo tar --zstd -xf nixos-rootfs.tar.zst -C /mnt/nixos --numeric-owner

# The NixOS initrd handles first-boot activation automatically.

sudo umount /mnt/fat32 /mnt/nixos
```

---

## 5. Add a hekate boot entry

Add the following to `hekate_ipl.ini` on the FAT32 partition (or use the provided `hekate_ipl.ini.snippet`):

```ini
[NixOS]
l4t=1
boot_prefixes=/switchroot/ubuntu/
id=nixos
rootdev=mmcblk0p2
rootfstype=ext4
icon=bootloader/res/icon_payload.bmp
```

> **Note:** `rootdev=mmcblk0p2` assumes NixOS is on partition 2. Adjust if your layout differs.
> The `boot_prefixes` path reuses the L4T Ubuntu bootstack — only the kernel (`Image`) and rootfs differ.

Boot from hekate → **More Configs** → **NixOS**.

---

## Building locally

If you want to build from source instead of using CI artifacts:

```bash
# Full NixOS system
nix build .#nixosConfigurations.switch-lite.config.system.build.toplevel

# Kernel only (uImage + DTBs)
nix build .#packages.aarch64-linux.kernel
```

Requires Nix ≥ 2.18 with flakes enabled.

### Updating kernel source pins

All 8 kernel source repos are pinned to specific commit SHAs in
`modules/l4t-kernel.nix`. To update a pin:

```bash
nix run nixpkgs#nix-prefetch-github -- <owner> <repo> --rev <new-sha>
nix run nixpkgs#nix-prefetch-git -- <url> --rev refs/heads/<branch>
```

Then replace the `rev` + `hash` fields in `modules/l4t-kernel.nix`.

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
├── .github/workflows/build.yml  # GH Actions CI – builds and publishes releases
├── flake.nix                    # Flake entry point, cross-compilation setup
├── flake.lock                   # Pinned nixpkgs (generated by nix flake lock)
├── configuration.nix            # systemd + GNOME + SSH + networking
├── hardware-configuration.nix   # Tegra T214 hardware, SD card layout
├── modules/
│   └── l4t-kernel.nix           # Custom L4T 4.9 kernel derivation
└── README.md                    # This file
```

---

## References

- [Switchroot wiki – L4T Ubuntu install guide](https://wiki.switchroot.org/wiki/linux/l4t-ubuntu-jammy-installation-guide)
- [theofficialgman/l4t-kernel-build-scripts](https://github.com/theofficialgman/l4t-kernel-build-scripts)
- [theofficialgman/switch-l4t-kernel-4.9](https://github.com/theofficialgman/switch-l4t-kernel-4.9)
- [Switchroot GitLab](https://gitlab.com/switchroot)
- [hekate releases](https://github.com/CTCaer/hekate/releases/latest)
