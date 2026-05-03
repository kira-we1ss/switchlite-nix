# Tegra L4T proprietary userspace libraries and firmware for Nintendo Switch Lite.
# Sourced from Switchroot Kubuntu Noble 5.1.2 (theofficialgman build).
#
# Contains:
#   - NVIDIA L4T Xorg driver (nvidia_drv.so)
#   - Tegra EGL/GL/CUDA libraries (/usr/lib/aarch64-linux-gnu/tegra{,-egl}/)
#   - xusb firmware (tegra210b01_xusb_firmware, tegra21x_xusb_firmware)
#   - GPU firmware (tegra21x/, nvidia/tegra210/)
#
# These blobs cannot be compiled from source and live outside the normal
# nixpkgs nvidia path because they target the L4T 4.9 kernel ABI, not
# mainline. The tarball is hosted as a GitHub release asset in this repo.

{ lib, stdenvNoCC, fetchurl, autoPatchelfHook
, xorg, libdrm, glibc
}:

let
  # sha256 of tegra-libs.tar.gz uploaded to the tegra-libs-v1 release
  tarballHash = "sha256-XWciO+aBcZkWXLGbx6ad9knpzyrJqpzbd1+gsPSD4zA=";
in

stdenvNoCC.mkDerivation {
  pname   = "tegra-l4t-libs";
  version = "32.3.1-kubuntu-noble-5.1.2";

  src = fetchurl {
    url    = "https://github.com/kira-we1ss/switchlite-nix/releases/download/tegra-libs-v1/tegra-libs.tar.gz";
    hash   = tarballHash;
  };

  # autopatchelf will fix up the .so RPATH so the tegra libs find each other.
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ xorg.libX11 xorg.libXext libdrm glibc ];

  # The tarball has paths like usr/lib/..., etc/X11/..., lib/firmware/...
  # relative to the rootfs root. Unpack and reorganise into $out.
  dontConfigure = true;
  dontBuild     = true;

  installPhase = ''
    runHook preInstall

    # Tegra userspace libraries
    mkdir -p $out/lib/aarch64-linux-gnu
    cp -r usr/lib/aarch64-linux-gnu/tegra     $out/lib/aarch64-linux-gnu/
    cp -r usr/lib/aarch64-linux-gnu/tegra-egl $out/lib/aarch64-linux-gnu/

    # Xorg nvidia driver
    mkdir -p $out/lib/xorg/modules/drivers
    cp usr/lib/xorg/modules/drivers/nvidia_drv.so $out/lib/xorg/modules/drivers/

    # Firmware blobs – installed to $out/lib/firmware so NixOS can
    # expose them via hardware.firmware
    mkdir -p $out/lib/firmware
    cp lib/firmware/tegra210b01_xusb_firmware $out/lib/firmware/
    cp lib/firmware/tegra21x_xusb_firmware    $out/lib/firmware/
    cp -r lib/firmware/tegra21x              $out/lib/firmware/
    cp -r lib/firmware/nvidia                $out/lib/firmware/

    runHook postInstall
  '';

  # autoPatchelf needs to know where the tegra libs are to resolve deps
  # among themselves.
  autoPatchelfIgnoreMissingDeps = true;

  meta = {
    description = "NVIDIA Tegra L4T proprietary libs and firmware for Switch Lite";
    platforms   = [ "aarch64-linux" ];
    license     = lib.licenses.unfreeRedistributable;
  };
}
