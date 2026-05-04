{ config, pkgs, lib, ... }:

{
  # ---------------------------------------------------------------
  # System identity
  # ---------------------------------------------------------------
  networking.hostName = "switch-lite";

  # ---------------------------------------------------------------
  # Boot – hekate loads uImage + DTB directly; we don't use GRUB or
  # systemd-boot here.  The bootloader section is intentionally
  # minimal; the real bootloader lives on the FAT32 partition and is
  # managed by hekate on the Switch side.
  # ---------------------------------------------------------------
  boot.loader.grub.enable  = false;
  boot.loader.generic-extlinux-compatible.enable = false;

  # Use the legacy bash-based initrd — simpler and more reliable on
  # non-standard hardware like the Switch where systemd-initrd may hang.
  boot.initrd.systemd.enable = false;

  # On initrd failure, dump logs to the FAT32 boot partition so we can
  # read them on a PC. The boot partition is the first MMC partition.
  boot.initrd.preFailCommands = ''
    mkdir -p /boot-fat32
    if mount -t vfat /dev/mmcblk0p1 /boot-fat32 2>/dev/null; then
      dmesg > /boot-fat32/nixos-boot.log
      cat /run/log/stage-1-init.log >> /boot-fat32/nixos-boot.log 2>/dev/null || true
      umount /boot-fat32
    fi
  '';

  # Kernel: use our custom L4T build instead of the stock NixOS kernel.
  # The package is injected via the overlay defined in flake.nix.
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.switch-l4t-kernel;

  # Extra kernel cmdline args (hekate can also pass these; this is the
  # NixOS-side default).  fbcon=map:0 ensures the framebuffer console
  # uses the built-in display.
  boot.kernelParams = [
    "fbcon=map:0"
    "video=1280x720@60"
    "console=tty0"
    "loglevel=7"
    "boot.shell_on_fail"
  ];

  # ---------------------------------------------------------------
  # Filesystems – defined in hardware-configuration.nix.
  # We declare the tmpfs and bind-mounts here that are always needed.
  # ---------------------------------------------------------------
  fileSystems."/tmp" = {
    device  = "tmpfs";
    fsType  = "tmpfs";
    options = [ "nosuid" "nodev" "size=512M" ];
  };

  # ---------------------------------------------------------------
  # Locale / time
  # ---------------------------------------------------------------
  time.timeZone              = "Europe/London"; # adjust as needed
  i18n.defaultLocale         = "en_GB.UTF-8";
  console.keyMap             = "uk";

  # ---------------------------------------------------------------
  # Users
  # ---------------------------------------------------------------
  users.mutableUsers = true;

  users.users.switch = {
    isNormalUser = true;
    description  = "Switch user";
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" "input" ];
    # Set a password with: passwd switch
    # Or pre-hash one: mkpasswd -m sha-512
    initialPassword = "changeme";
  };

  # Allow passwordless sudo for wheel (convenient on a single-user device)
  security.sudo.wheelNeedsPassword = false;

  # ---------------------------------------------------------------
  # Desktop: GNOME + GDM on Wayland
  # ---------------------------------------------------------------
  services.xserver = {
    enable       = true;
    # Empty: prevents NixOS from generating any Device/Screen/ServerLayout
    # sections (which would conflict with ours below). No nixpkgs nvidia
    # package is pulled in either.
    videoDrivers = [];

    displayManager.gdm = {
      enable  = true;
      wayland = false;
    };

    desktopManager.gnome.enable = true;

    displayManager.xserverArgs = [ "-ignoreABI" ];
  };

  # Add tegra-l4t-libs ModulePath to the generated Files section.
  services.xserver.modules = [ pkgs.tegra-l4t-libs ];

  # Touch coordinate transform for 90° CW rotation.
  services.xserver.inputClassSections = [''
    Identifier "touchscreen rotate"
    MatchProduct "touchscreen"
    Option "TransformationMatrix" "0 1 0 -1 0 1 0 0 1"
  ''];

  # Minimal Device section matching Kubuntu's xorg.conf exactly.
  # No Screen/ServerLayout here — those go in xorg.conf.d below.
  services.xserver.config = lib.mkAfter ''
    Section "Module"
      Disable    "dri"
      SubSection "extmod"
        Option   "omit xfree86-dga"
      EndSubSection
    EndSection

    Section "Device"
      Identifier "Tegra0"
      Driver     "nvidia"
      Option     "AllowUnofficialGLXProtocol" "true"
      Option     "DPMS" "false"
      Option     "AllowEmptyInitialConfiguration" "true"
      Option     "Monitor-DSI-0" "Monitor0"
      Option     "Monitor-DP-0"  "Monitor1"
    EndSection
  '';

  # Screen, Monitor, and touch config in xorg.conf.d — mirrors Kubuntu exactly.
  environment.etc."X11/xorg.conf.d/10-monitor.conf".text = ''
    Section "Monitor"
      Identifier "Monitor0"
      ModelName  "DFP-0"
    EndSection

    Section "Monitor"
      Identifier "Monitor1"
      Option     "Enable" "false"
    EndSection

    Section "Screen"
      Identifier   "Screen0"
      Device       "Tegra0"
      Monitor      "Monitor0"
      DefaultDepth 24
      Option       "metamodes" "DSI-0: nvidia-auto-select @1280x720 +0+0 {ViewPortIn=1280x720, ViewPortOut=720x1280+0+0, Rotation=90}"
      SubSection   "Display"
        Depth      24
      EndSubSection
    EndSection
  '';

  environment.etc."X11/xorg.conf.d/11-touchscreen.conf".text = ''
    Section "InputClass"
      Identifier  "calibration"
      MatchProduct "touchscreen"
      Option "TransformationMatrix" "0 1 0 -1 0 1 0 0 1"
    EndSection
  '';

  # Tegra proprietary userspace libs (EGL, CUDA, display libs).
  hardware.opengl = {
    enable        = true;
    driSupport    = true;
    extraPackages = [ pkgs.tegra-l4t-libs ];
  };

  # Tell the dynamic linker where the Tegra libs live in the Nix store.
  hardware.opengl.extraPackages32 = [];  # aarch64 — no 32-bit
  environment.etc."ld.so.conf.d/tegra.conf".text = ''
    ${pkgs.tegra-l4t-libs}/lib/aarch64-linux-gnu/tegra
    ${pkgs.tegra-l4t-libs}/lib/aarch64-linux-gnu/tegra-egl
  '';

  # xusb and GPU firmware for USB-C and nvgpu, plus any future blobs.
  hardware.firmware = [ pkgs.tegra-l4t-libs ];

  # Tegra device node udev rules — required for nvgpu/nvhost devices to appear
  # with correct permissions so the L4T nvidia X driver can open them.
  services.udev.extraRules = ''
    KERNEL=="nvmap",           OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="nvhost-ctrl",     OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="nvhost-ctrl-gpu", OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="nvhost-gpu",      OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="nvhost-vic",      OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="nvhost-msenc",    OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="nvhost-nvdec",    OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="nvhost-nvjpg",    OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="nvhost-dbg-gpu",  OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="nvhost-prof-gpu", OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="tegra_dc_ctrl",   OWNER="root", GROUP="video", MODE="0660"
    KERNEL=="tegra_dc_0",      OWNER="root", GROUP="video", MODE="0660"
  '';

  # USB gadget networking for SSH over USB-C.
  # Creates usb0 as RNDIS device at 192.168.7.1 (Switch side).
  # Connect USB-C to laptop, then: ssh switch@192.168.7.1
  systemd.services.usb-gadget-rndis = {
    description = "USB gadget RNDIS network interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "usb-gadget-rndis-start" ''
        set -e
        ${pkgs.kmod}/bin/modprobe g_ether host_addr=42:63:65:13:34:56 dev_addr=42:63:65:13:34:57 || true
        sleep 1
        ${pkgs.iproute2}/bin/ip link set usb0 up || true
        ${pkgs.iproute2}/bin/ip addr add 192.168.7.1/24 dev usb0 || true
      '';
    };
  };

  # GDM needs access to /dev/fb0 on Tegra (no DRM/KMS).
  # Use groups.video.members instead of extraGroups because gdm is a
  # system-managed user and extraGroups is ignored for it.
  users.groups.video.members = [ "gdm" "switch" ];

  # nsncd needs /var/empty to exist
  system.activationScripts.varEmpty = ''
    mkdir -p /var/empty
    chmod 555 /var/empty
  '';
  services.journald.extraConfig = ''
    Storage=persistent
    Compress=no
  '';
  # Remove this once the system boots reliably.
  systemd.services.dump-boot-log = {
    description = "Dump boot journal to FAT32 for debugging";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "systemd-journald.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "dump-boot-log" ''
        mkdir -p /boot-fat32
        mount -t vfat /dev/mmcblk0p1 /boot-fat32 2>/dev/null || true
        journalctl -b --no-pager > /boot-fat32/nixos-stage2.log 2>&1 || true
        umount /boot-fat32 2>/dev/null || true
      '';
    };
  };
  environment.variables = {
    GDK_SCALE          = "1";
    GDK_DPI_SCALE      = "1.5";
    GNOME_SHELL_SLOWDOWN_FACTOR = "1";
  };

  # Disable GNOME's power-saving blanking – useful during initial setup
  # (you can re-enable it once everything is stable).
  services.gnome.gnome-settings-daemon.enable = true;

  # ---------------------------------------------------------------
  # Networking
  # ---------------------------------------------------------------
  networking.networkmanager.enable = true;

  # Wi-Fi: BCM4354 (Mariko/Switch Lite).
  # The firmware blobs are shipped inside the L4T kernel tree as
  # ihex files and compiled in; no extra firmware package is needed.

  # ---------------------------------------------------------------
  # Audio
  # ---------------------------------------------------------------
  # PipeWire replaces PulseAudio.  Audio on Mariko may need extra
  # work (the Tegra ADSP is involved); this gets the stack in place.
  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = false; # aarch64, no 32-bit compat needed
    pulse.enable      = true;
  };
  hardware.pulseaudio.enable = false; # conflicts with PipeWire

  # ---------------------------------------------------------------
  # SSH (useful for initial headless debugging over USB or Wi-Fi)
  # ---------------------------------------------------------------
  services.openssh = {
    enable               = true;
    settings.PasswordAuthentication = true;
    settings.PermitRootLogin        = "no";
  };

  # ---------------------------------------------------------------
  # Swap (small, on the SD card – helps with memory pressure)
  # ---------------------------------------------------------------
  swapDevices = [{
    device = "/dev/disk/by-partlabel/swap";
    # If you didn't create a swap partition, comment this out and use
    # a swapfile instead:
    # device = "/swapfile";
    # size   = 2048; # MiB
  }];

  # ---------------------------------------------------------------
  # Packages
  # ---------------------------------------------------------------
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim nano git curl wget htop lsof pciutils usbutils
    # Filesystem tools
    e2fsprogs dosfstools parted
    # Networking
    networkmanager iw iproute2
    # GNOME extras
    gnome.gnome-tweaks
    gnome.gnome-terminal
    # JoyCon support (HID-Nintendo driver is in the L4T kernel;
    # joycond provides the udev side)
    joycond
  ];

  # ---------------------------------------------------------------
  # Fonts – small but readable set for the 720p display
  # ---------------------------------------------------------------
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    liberation_ttf
  ];

  # ---------------------------------------------------------------
  # Power management
  # ---------------------------------------------------------------
  # The Switch Lite has no battery indicator in mainline; disable
  # anything that assumes ACPI battery info to avoid spurious errors.
  services.upower.enable = lib.mkForce false;

  # ---------------------------------------------------------------
  # NixOS state version – do not change after first install
  # ---------------------------------------------------------------
  system.stateVersion = "24.05";

  nixpkgs.config.allowUnfree = true;
}
