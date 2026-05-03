# xorg-server 1.20.13 — required for the NVIDIA L4T Xorg driver (ABI 24).
# NixOS 24.05 ships xorg-server 1.21.x (ABI 25), which is incompatible.
# This derivation overrides just the source, keeping all the nixpkgs patches
# and build infrastructure intact.

{ xorg, fetchurl, lib }:

xorg.xorgserver.overrideAttrs (old: rec {
  pname   = "xorg-server";
  version = "1.20.13";

  src = fetchurl {
    url    = "https://xorg.freedesktop.org/archive/individual/xserver/xorg-server-${version}.tar.gz";
    hash   = "sha256-JvgB9NkiFplfOJhzzztOkAac9j6UvF3Qnrv3/X4d3MI=";
  };

  # 1.20.x uses automake, not meson. The meson flags from 1.21 don't apply.
  # Keep existing configureFlags but strip any meson-specific ones.
  configureFlags = [
    "--enable-kdrive"
    "--enable-xephyr"
    "--enable-xcsecurity"
    "--enable-xorg"
    "--enable-glamor"
    "--enable-xvfb"
    "--enable-xnest"
    "--with-xkb-bin-directory=${xorg.xkbcomp}/bin"
    "--with-xkb-path=${xorg.xkeyboardconfig}/share/X11/xkb"
    "--with-xkb-output=$out/share/X11/xkb/compiled"
    "--with-log-dir=/var/log"
    "--with-sdkdir=$(dev)/include/xorg"
  ];

  # 1.20.x does not use meson
  nativeBuildInputs = lib.filter
    (x: !(lib.isDerivation x && lib.hasInfix "meson" (x.name or "")))
    (old.nativeBuildInputs or []);

  # Drop the logdir-during-build patch (doesn't apply to 1.20.x autotools).
  patches = lib.filter
    (p: !(lib.isDerivation p && lib.hasInfix "logdir" (p.name or "")))
    (old.patches or []);

  # Fix 'Bool bool' field conflicting with C99 bool keyword introduced by
  # mesa 24+ dri_interface.h including <stdbool.h>. Rename the struct field
  # and all references to 'boolean' across the relevant source files.
  prePatch = (old.prePatch or "") + ''
    sed -i 's/Bool bool;/Bool boolean;/g' hw/xfree86/common/xf86Opt.h
    sed -i 's/value\.bool/value.boolean/g' \
      hw/xfree86/common/xf86Option.c \
      hw/xwin/winconfig.c
  '';
})
