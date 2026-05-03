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

  # The dont-create-logdir patch may not apply cleanly to 1.20.x; drop it.
  # 1.20.x creates the logdir at runtime, not build time.
  patches = lib.filter
    (p: !(lib.isDerivation p && lib.hasInfix "logdir" (p.name or "")))
    (old.patches or []);
})
