# L4T kernel derivation for Nintendo Switch (Tegra T210/T214)
# Based on theofficialgman's Switch L4T kernel fork of the NVIDIA Tegra BSP kernel (4.9.140-l4t)
# Sources mirror the l4t-kernel-build-scripts by theofficialgman
# Targets both Erista (T210) and Mariko/Switch Lite (T214/tegra210b01) hardware.

{ lib, stdenv, fetchFromGitHub, fetchgit
, rsync, perl, python3, bc, bison, flex, openssl, elfutils, kmod
, ubootTools, dtc
# NixOS passes various extra arguments to kernel derivations
# (kernelPatches, features, randstructSeed, …); accept them all.
, ...
}:

let
  # ---------------------------------------------------------------
  # Source pins – all resolved to specific commit SHAs for
  # reproducibility.  To update, re-run nix-prefetch-github /
  # nix-prefetch-git against the relevant branch and replace both
  # the rev and hash fields.
  # ---------------------------------------------------------------

  kernelSrc = fetchFromGitHub {
    owner = "theofficialgman";
    repo  = "switch-l4t-kernel-4.9";
    rev   = "6f926926d94a54aa6f9128234dd1a3833f6828d8";
    hash  = "sha256-usEQGVq4HW4cRQpwSmq4VZeAzthuVaLgYjL38W2iafM=";
  };

  nvidiaSrc = fetchFromGitHub {
    owner = "theofficialgman";
    repo  = "switch-l4t-kernel-nvidia";
    # Pinned to the latest commit on linux-dev as of 2026-05-02
    rev   = "d6b4e81575fd60d8271494950883c94c673bf421";
    hash  = "sha256-4gac2kHwOAVunWQ07CNptl6COIA39ZYgD6vgPF6p0QI=";
  };

  platformNxSrc = fetchFromGitHub {
    owner = "theofficialgman";
    repo  = "switch-l4t-platform-t210-nx";
    # Pinned to the latest commit on linux-dev as of 2026-05-02
    rev   = "30a809dcf0b94765298d078c2e63939eeded1250";
    hash  = "sha256-ENHzqBBrltFamYOZi4y5IWmKj72v9pvAvj06IGufWSI=";
  };

  nvgpuSrc = fetchgit {
    url = "https://gitlab.com/switchroot/kernel/l4t-kernel-nvgpu.git";
    rev = "1ae0167d360287ca78f5a2572f0de42594140312"; # linux-3.4.0-r32.5 branch HEAD
    hash = "sha256-SK/x/T2mMf9Kcz9rOXbyjPb84QqJf1QaD+lwSFQ+eq8=";
  };

  socT210Src = fetchgit {
    url = "https://gitlab.com/switchroot/kernel/l4t-soc-t210.git";
    rev = "0d7816046cb06b637a3b70381a5e4994fd897c35"; # l4t/l4t-r32.5 branch HEAD
    hash = "sha256-CcAxoGearjNNKDgB77oTKtmWDI+u358lAAvrJB9/sUE=";
  };

  socTegraSrc = fetchgit {
    url = "https://gitlab.com/switchroot/kernel/l4t-soc-tegra.git";
    rev = "d2692b96d3a89e26d3bad94eb7e6bc4caccbdbdb"; # l4t/l4t-r32.5 branch HEAD
    hash = "sha256-uXBk9Rfbhxc8fBEJukwrcH5xNcA0hlEzAMSW9wQ3NIY=";
  };

  platformTegraSrc = fetchgit {
    url = "https://gitlab.com/switchroot/kernel/l4t-platform-tegra-common.git";
    rev = "1677f40a0b1bfa7c7273143b0f4944de28b73444"; # l4t/l4t-r32.5 branch HEAD
    hash = "sha256-sEZ51GyLvtS8pYP3jxATZDCJ7mpUI02VL3zFeWN1w1M=";
  };

  platformT210CommonSrc = fetchgit {
    url = "https://gitlab.com/switchroot/kernel/l4t-platform-t210-common.git";
    rev = "846ce66ee941b49ff32bc721e4c8cc99eea2e979"; # l4t/l4t-r32.5 branch HEAD
    hash = "sha256-QFNOTrFqzatnjZZzvAl9eq7R7bT+6s74fz+1sRpuAHM=";
  };

in

stdenv.mkDerivation rec {
  pname   = "switch-l4t-kernel";
  version = "4.9.140-l4t";

  src = kernelSrc;

  # Build-time dependencies
  depsBuildBuild = [ stdenv.cc ];
  nativeBuildInputs = [
    stdenv.cc
    stdenv.cc.bintools  # provides objdump, objcopy, etc.
    rsync perl python3 bc bison flex openssl elfutils kmod
    ubootTools dtc
  ];

  # Tegra-specific optimisation flags (matching the upstream build script).
  # gcc7Stdenv is used to match theofficialgman's Linaro GCC 7 toolchain.
  KCFLAGS = "-march=armv8-a+simd+crypto+crc -mtune=cortex-a57 "
          + "--param=l1-cache-line-size=64 --param=l1-cache-size=32 "
          + "--param=l2-cache-size=2048";

  ARCH = "arm64";
  # Derive CROSS_COMPILE from the actual toolchain so it matches whatever
  # prefix nixpkgs chose (e.g. aarch64-unknown-linux-gnu-).
  CROSS_COMPILE = "${stdenv.cc.targetPrefix}";

  # ---------------------------------------------------------------
  # Layout the multi-repo source tree the Makefile expects
  # ---------------------------------------------------------------
  # ---------------------------------------------------------------
  # Recreate the exact directory layout expected by the kernel
  # Makefile, mirroring l4t-kernel-build-scripts:
  #
  #   workdir/
  #     kernel-4.9/          ← kernel source  (build runs from here)
  #     nvidia/              ← nvidia out-of-tree modules (../nvidia)
  #     nvgpu/               ← nvgpu driver
  #     hardware/
  #       nvidia/
  #         platform/t210/nx/
  #         platform/t210/common/
  #         platform/tegra/common/
  #         soc/t210/
  #         soc/tegra/
  # ---------------------------------------------------------------
  unpackPhase = ''
    mkdir -p workdir/hardware/nvidia/platform/t210
    mkdir -p workdir/hardware/nvidia/platform/tegra
    mkdir -p workdir/hardware/nvidia/soc

    cp -r ${kernelSrc}            workdir/kernel-4.9
    cp -r ${nvidiaSrc}            workdir/nvidia
    cp -r ${platformNxSrc}        workdir/hardware/nvidia/platform/t210/nx
    cp -r ${nvgpuSrc}             workdir/nvgpu
    cp -r ${socT210Src}           workdir/hardware/nvidia/soc/t210
    cp -r ${socTegraSrc}          workdir/hardware/nvidia/soc/tegra
    cp -r ${platformTegraSrc}     workdir/hardware/nvidia/platform/tegra/common
    cp -r ${platformT210CommonSrc} workdir/hardware/nvidia/platform/t210/common

    chmod -R u+w workdir
    sourceRoot=$PWD/workdir/kernel-4.9
  '';

  configurePhase = ''
    make tegra_linux_defconfig ARCH=arm64
  '';

  buildPhase = ''
    # tegra-dtstree is relative to the kernel source dir (workdir/kernel-4.9/).
    # ../hardware/nvidia resolves to workdir/hardware/nvidia.
    make -j$NIX_BUILD_CORES tegra-dtstree="../hardware/nvidia" ARCH=arm64
  '';

  installPhase = ''
    # Install kernel image (uImage format expected by hekate)
    mkdir -p $out/boot $out/lib

    mkimage -A arm64 -O linux -T kernel -C gzip \
      -a 0x80200000 -e 0x80200000 \
      -n "switch-l4t-${version}" \
      -d arch/arm64/boot/zImage \
      $out/boot/uImage

    # NixOS internals expect the kernel image at $out/Image (arm64 convention)
    cp arch/arm64/boot/Image $out/Image

    # Install DTBs for all Switch variants
    # tegra210b01-vali = Switch Lite (HDH)
    # tegra210b01-fric = Switch Lite (HDH with NVENC fuse variant)
    # tegra210-odin    = OG Switch (for completeness)
    # tegra210b01-odin = OG Switch Mariko revision
    for dtb in \
        tegra210b01-vali \
        tegra210b01-fric \
        tegra210-odin \
        tegra210b01-odin; do
      if [ -f arch/arm64/boot/dts/''${dtb}.dtb ]; then
        cp arch/arm64/boot/dts/''${dtb}.dtb $out/boot/
      fi
    done

    # Install kernel modules
    make modules_install INSTALL_MOD_PATH=$out ARCH=arm64
    # Remove broken symlinks (build/source) that point back into the build dir
    rm -f $out/lib/modules/${version}/build \
          $out/lib/modules/${version}/source
  '';

  meta = with lib; {
    description  = "Linux 4.9 L4T kernel patched for Nintendo Switch (Tegra T210/T214)";
    homepage     = "https://github.com/theofficialgman/switch-l4t-kernel-4.9";
    license      = licenses.gpl2Only;
    platforms    = [ "aarch64-linux" ];
    maintainers  = [];
  };

  # passthru attributes expected by NixOS's linuxPackagesFor and kernel.nix
  passthru = {
    features        = {};
    kernelAtLeast   = lib.versionAtLeast version;
    kernelOlder     = lib.versionOlder   version;
    # Used by bootspec and other modules to locate /lib/modules/<modDirVersion>
    modDirVersion   = version;
    inherit version;
  };
}
