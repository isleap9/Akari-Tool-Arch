#!/usr/bin/env bash
#
# akari-install.sh — Arch Linux installer, live-ISO only.
#
# This is NOT akari-setup.sh. Everything akari-setup does is idempotent and
# reversible; everything here is destructive and one-shot. The two are kept
# apart on purpose. The only thing they share is the hand-off at the end,
# where this script calls akari-setup inside the new system's chroot.
#
# Usage:
#   ./akari-install.sh env-check              # live ISO? UEFI? network?
#   ./akari-install.sh disks                  # installable disks
#   ./akari-install.sh detect-tz              # best-guess timezone
#   ./akari-install.sh plan  <config-file>    # exactly what apply would do
#   ./akari-install.sh apply <config-file>    # partition, install, configure
#
# The config file is plain KEY=value. See sample_config() below.
#
set -uo pipefail

AKARI_INSTALL_VERSION="0.1.0"
LOG=/var/log/akari-install.log

# ---------------------------------------------------------------- emit

emit() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }
say()  { printf ':: %s\n' "$*" | tee -a "$LOG" 2>/dev/null || printf ':: %s\n' "$*"; }
die()  { printf '!! %s\n' "$*" >&2; exit 1; }

# Run a command, echoing it first, and abort the install if it fails.
# Nothing here is safe to "continue past".
run() {
  printf '   $ %s\n' "$*" | tee -a "$LOG" >/dev/null 2>&1
  printf '   %s$ %s%s\n' "${DIM:-}" "$*" "${RST:-}"
  "$@" || die "failed: $*"
}

# ---------------------------------------------------------------- environment

is_live_iso() {
  [[ -d /run/archiso ]] && return 0
  grep -qi archiso /proc/cmdline 2>/dev/null && return 0
  [[ -f /etc/arch-release && $(cat /etc/hostname 2>/dev/null) == archiso ]] && return 0
  return 1
}

is_uefi() { [[ -d /sys/firmware/efi/efivars ]]; }

# The device the live system itself booted from — never a valid target.
iso_device() {
  local src
  src=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null) || return 0
  [[ -n $src ]] || return 0
  lsblk -no PKNAME "$src" 2>/dev/null | head -1
}

cmd_env_check() {
  if is_live_iso; then
    emit live ok "Running in the Arch live environment"
  else
    emit live fail "NOT a live ISO — this script only runs from the Arch installer image"
  fi
  if [[ $EUID -eq 0 ]]; then
    emit root ok "Running as root"
  else
    emit root fail "Must run as root"
  fi
  if is_uefi; then
    emit firmware ok "UEFI system"
  else
    emit firmware warn "Legacy BIOS — GRUB will be used, systemd-boot is unavailable"
  fi
  if ping -c1 -W3 archlinux.org &>/dev/null || curl -sfm 5 -o /dev/null https://archlinux.org; then
    emit network ok "Online"
  else
    emit network fail "No network — connect first (iwctl for wifi, or plug in ethernet)"
  fi
  local n; n=$(cmd_disks | wc -l)
  if (( n > 0 )); then
    emit disks ok "$n installable disk(s) found"
  else
    emit disks fail "No installable disk found"
  fi
  local mem; mem=$(awk '/MemTotal/ {printf "%.1f", $2/1048576}' /proc/meminfo)
  emit memory ok "${mem} GiB RAM"
}

# DSK|device|size|model|transport|blocked-reason
cmd_disks() {
  local iso; iso=$(iso_device)
  local name size model tran ro mp reason
  while read -r name; do
    [[ -z $name ]] && continue
    size=$(lsblk -dno SIZE "/dev/$name" 2>/dev/null | head -1); size="${size//[[:space:]]/}"
    model=$(lsblk -dno MODEL "/dev/$name" 2>/dev/null | head -1)
    tran=$(lsblk -dno TRAN  "/dev/$name" 2>/dev/null | head -1)
    ro=$(lsblk -dno RO      "/dev/$name" 2>/dev/null | head -1)
    # lsblk pads its columns; strip so the fields are usable as data
    model="${model#"${model%%[![:space:]]*}"}"; model="${model%"${model##*[![:space:]]}"}"
    tran="${tran//[[:space:]]/}"; ro="${ro//[[:space:]]/}"
    reason=""
    [[ $name == "$iso" ]] && reason="live USB — this is the disk you booted from"
    [[ $ro == 1 ]] && reason="read-only device"
    mp=$(lsblk -no MOUNTPOINT "/dev/$name" 2>/dev/null | grep -v '^$' | head -1)
    [[ -n $mp && -z $reason ]] && reason="in use (mounted at $mp)"
    printf 'DSK|/dev/%s|%s|%s|%s|%s\n' \
      "$name" "${size:-?}" "${model:-unknown}" "${tran:-?}" "$reason"
  done < <(lsblk -dno NAME --nodeps 2>/dev/null | grep -Ev '^(loop|sr|ram|zram)')
}

cmd_detect_tz() {
  local tz
  tz=$(curl -sfm 4 https://ipapi.co/timezone 2>/dev/null)
  [[ $tz =~ ^[A-Za-z_]+/[A-Za-z_/+-]+$ ]] && { echo "$tz"; return; }
  echo "UTC"
}

# ---------------------------------------------------------------- config

sample_config() {
  cat <<'CFG'
# akari-install config
DISK=/dev/nvme0n1
FS=btrfs              # btrfs | ext4
SWAP=zram             # zram | none
BOOTLOADER=systemd-boot   # systemd-boot | grub
KERNEL=linux-zen      # linux | linux-zen | linux-lts
HOSTNAME=akari
USERNAME=user
USERPASS=
ROOTPASS=
TIMEZONE=UTC
LOCALE=en_US.UTF-8
KEYMAP=us
DESKTOP=none          # none | hyprland | kde | gnome
GAMING=0              # 1 = run akari-setup's gaming apply in the new system
AURHELPER=none        # none | paru
CONFIRM=              # must literally be WIPE before apply will touch a disk
CFG
}

load_config() {
  local f=$1
  [[ -r $f ]] || die "cannot read config: $f"
  # Only KEY=value lines; nothing is evaluated as shell.
  DISK=""; FS=btrfs; SWAP=zram; BOOTLOADER=systemd-boot; KERNEL=linux
  HOSTNAME=akari; USERNAME=""; USERPASS=""; ROOTPASS=""
  TIMEZONE=UTC; LOCALE=en_US.UTF-8; KEYMAP=us; DESKTOP=none
  GAMING=0; AURHELPER=none; CONFIRM=""
  local line k v
  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    k=${line%%=*}; v=${line#*=}
    k=${k//[[:space:]]/}
    case $k in
      DISK|FS|SWAP|BOOTLOADER|KERNEL|HOSTNAME|USERNAME|USERPASS|ROOTPASS|\
      TIMEZONE|LOCALE|KEYMAP|DESKTOP|GAMING|AURHELPER|CONFIRM)
        printf -v "$k" '%s' "$v" ;;
      *) : ;;
    esac
  done < "$f"
}

validate_config() {
  [[ -n $DISK ]]           || die "DISK is not set"
  [[ -b $DISK ]]           || die "$DISK is not a block device"
  [[ -n $USERNAME ]]       || die "USERNAME is not set"
  [[ $USERNAME =~ ^[a-z_][a-z0-9_-]*$ ]] || die "invalid USERNAME: $USERNAME"
  [[ -n $USERPASS ]]       || die "USERPASS is empty"
  [[ -n $ROOTPASS ]]       || die "ROOTPASS is empty"
  [[ $HOSTNAME =~ ^[a-zA-Z0-9-]+$ ]] || die "invalid HOSTNAME: $HOSTNAME"
  case $FS in btrfs|ext4) ;; *) die "FS must be btrfs or ext4" ;; esac
  case $SWAP in zram|none) ;; *) die "SWAP must be zram or none" ;; esac
  case $DESKTOP in none|hyprland|kde|gnome) ;; *) die "unknown DESKTOP: $DESKTOP" ;; esac

  if ! is_uefi && [[ $BOOTLOADER == systemd-boot ]]; then
    die "systemd-boot needs UEFI; this machine booted in BIOS mode — use grub"
  fi

  # Refuse the live USB and anything currently in use.
  local iso; iso=$(iso_device)
  [[ -n $iso && $DISK == "/dev/$iso" ]] && die "$DISK is the live USB you booted from"
  local mp
  mp=$(lsblk -no MOUNTPOINT "$DISK" 2>/dev/null | grep -v '^$' | head -1)
  [[ -n $mp ]] && die "$DISK has a mounted partition ($mp) — unmount it first"
}

# ---------------------------------------------------------------- packages

ucode_pkg() {
  if grep -qi 'vendor_id.*AMD' /proc/cpuinfo; then echo amd-ucode
  elif grep -qi 'vendor_id.*Intel' /proc/cpuinfo; then echo intel-ucode
  fi
}

# Everything pacstrap installs, assembled from the config.
base_packages() {
  local -a p=( base base-devel linux-firmware "$KERNEL" "${KERNEL}-headers"
               networkmanager sudo nano vim git curl pciutils
               man-db man-pages texinfo )
  local uc; uc=$(ucode_pkg); [[ -n $uc ]] && p+=( "$uc" )
  [[ $FS == btrfs ]] && p+=( btrfs-progs )
  [[ $SWAP == zram ]] && p+=( zram-generator )
  if [[ $BOOTLOADER == grub ]]; then
    p+=( grub )
    is_uefi && p+=( efibootmgr )
  else
    p+=( efibootmgr )
  fi
  case $DESKTOP in
    hyprland) p+=( hyprland xdg-desktop-portal-hyprland kitty wofi waybar
                   polkit-kde-agent qt5-wayland qt6-wayland
                   pipewire pipewire-pulse wireplumber
                   ttf-jetbrains-mono-nerd greetd greetd-tuigreet ) ;;
    kde)      p+=( plasma-meta konsole dolphin sddm
                   pipewire pipewire-pulse wireplumber ) ;;
    gnome)    p+=( gnome gnome-tweaks gdm
                   pipewire pipewire-pulse wireplumber ) ;;
  esac
  printf '%s\n' "${p[@]}"
}

# ---------------------------------------------------------------- partitions

# nvme0n1 -> nvme0n1p1 ; sda -> sda1
part_name() {
  local disk=$1 n=$2
  if [[ $disk =~ [0-9]$ ]]; then echo "${disk}p${n}"; else echo "${disk}${n}"; fi
}

# ---------------------------------------------------------------- plan

cmd_plan() {
  load_config "$1"
  local uc; uc=$(ucode_pkg)
  local esp root
  esp=$(part_name "$DISK" 1); root=$(part_name "$DISK" 2)

  echo "== Plan: install Arch Linux on $DISK =="
  echo ""
  echo "!! EVERYTHING ON $DISK WILL BE DESTROYED."
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DISK" 2>/dev/null | sed 's/^/   /'
  echo ""
  echo "Firmware:    $(is_uefi && echo UEFI || echo "BIOS (legacy)")"
  echo "Bootloader:  $BOOTLOADER"
  echo "Kernel:      $KERNEL"
  echo "Filesystem:  $FS"
  echo "Swap:        $SWAP"
  echo "Desktop:     $DESKTOP"
  echo ""
  echo "Partitions to create:"
  if is_uefi; then
    echo "  $esp   1 GiB   FAT32, EFI system partition, mounted at /boot"
  else
    echo "  $esp   1 MiB   BIOS boot partition (GRUB core.img)"
  fi
  echo "  $root  rest    $FS, mounted at /"
  if [[ $FS == btrfs ]]; then
    echo "         btrfs subvolumes: @ @home @var_log @var_pkg @snapshots"
    echo "         mounted noatime,compress=zstd:3 — snapper-friendly layout"
  fi
  echo ""
  echo "Then:"
  echo "  1. pacstrap $(base_packages | wc -l) packages${uc:+ (incl. $uc microcode)}"
  echo "  2. genfstab -U"
  echo "  3. timezone $TIMEZONE, locale $LOCALE, keymap $KEYMAP, hostname $HOSTNAME"
  echo "  4. mkinitcpio -P"
  echo "  5. root password, user '$USERNAME' in wheel, sudo for wheel"
  echo "  6. enable NetworkManager$([[ $DESKTOP != none ]] && echo " and the display manager")"
  echo "  7. install $BOOTLOADER"
  [[ $AURHELPER == paru ]] && echo "  8. build paru as $USERNAME"
  [[ $GAMING == 1 ]] && echo "  9. run akari-setup 'apply gaming' inside the new system"
  echo ""
  echo "Packages:"
  base_packages | paste -sd' ' - | fold -s -w 72 | sed 's/^/  /'
  echo ""
  if [[ $CONFIRM != WIPE ]]; then
    echo "CONFIRM is not set to WIPE — apply would refuse. Nothing has been written."
  fi
}

# ---------------------------------------------------------------- apply

cmd_apply() {
  load_config "$1"
  validate_config
  [[ $CONFIRM == WIPE ]] || die "refusing: CONFIRM is not set to WIPE"
  is_live_iso || die "refusing: not running from the Arch live ISO"
  [[ $EUID -eq 0 ]] || die "must run as root"

  mkdir -p "$(dirname "$LOG")"; : > "$LOG"
  say "Akari installer $AKARI_INSTALL_VERSION — target $DISK"

  local esp root
  esp=$(part_name "$DISK" 1); root=$(part_name "$DISK" 2)

  # -- clock & mirrors ---------------------------------------------------
  say "Synchronising clock"
  timedatectl set-ntp true 2>/dev/null || true

  # -- partition ---------------------------------------------------------
  say "Wiping and partitioning $DISK"
  run swapoff -a
  umount -R /mnt 2>/dev/null || true
  run sgdisk --zap-all "$DISK"
  run wipefs -a "$DISK"
  if is_uefi; then
    run sgdisk -n 1:0:+1G   -t 1:ef00 -c 1:EFI  "$DISK"
  else
    run sgdisk -n 1:0:+1M   -t 1:ef02 -c 1:BIOS "$DISK"
  fi
  run sgdisk -n 2:0:0 -t 2:8300 -c 2:ROOT "$DISK"
  run partprobe "$DISK"
  udevadm settle 2>/dev/null || sleep 2

  # -- filesystems -------------------------------------------------------
  if is_uefi; then
    say "Formatting EFI system partition"
    run mkfs.fat -F32 -n EFI "$esp"
  fi

  say "Formatting root as $FS"
  if [[ $FS == btrfs ]]; then
    run mkfs.btrfs -f -L ROOT "$root"
    run mount "$root" /mnt
    local sv
    for sv in @ @home @var_log @var_pkg @snapshots; do
      run btrfs subvolume create "/mnt/$sv"
    done
    run umount /mnt
    local opts="noatime,compress=zstd:3,space_cache=v2"
    run mount -o "$opts,subvol=@" "$root" /mnt
    run mkdir -p /mnt/home /mnt/var/log /mnt/var/cache/pacman/pkg /mnt/.snapshots /mnt/boot
    run mount -o "$opts,subvol=@home"      "$root" /mnt/home
    run mount -o "$opts,subvol=@var_log"   "$root" /mnt/var/log
    run mount -o "$opts,subvol=@var_pkg"   "$root" /mnt/var/cache/pacman/pkg
    run mount -o "$opts,subvol=@snapshots" "$root" /mnt/.snapshots
  else
    run mkfs.ext4 -F -L ROOT "$root"
    run mount "$root" /mnt
    run mkdir -p /mnt/boot
  fi
  is_uefi && run mount "$esp" /mnt/boot

  # -- base system -------------------------------------------------------
  say "Installing the base system (this is the long part)"
  local -a pkgs; mapfile -t pkgs < <(base_packages)
  run pacstrap -K /mnt "${pkgs[@]}"

  say "Generating fstab"
  genfstab -U /mnt >> /mnt/etc/fstab || die "genfstab failed"

  # -- configure inside the chroot --------------------------------------
  # Written as a file rather than a heredoc pipe so passwords never appear
  # in a process listing. 0600, and deleted before we finish.
  say "Configuring the new system"
  local croot=/mnt/akari-chroot.sh
  write_chroot_script "$croot" "$root"
  chmod 700 "$croot"
  arch-chroot /mnt /bin/bash /akari-chroot.sh 2>&1 | tee -a "$LOG"
  local rc=${PIPESTATUS[0]}
  rm -f "$croot"
  (( rc == 0 )) || die "configuration inside the chroot failed (exit $rc)"

  # -- optional: hand off to akari-setup --------------------------------
  if [[ $GAMING == 1 ]]; then
    handoff_gaming
  fi

  cp "$LOG" /mnt/var/log/ 2>/dev/null || true
  say "Installation finished."
  echo ""
  echo "Next: umount -R /mnt && reboot"
  echo "Remove the USB stick at the reboot prompt."
}

# The gaming hand-off. This is the entire reason the installer lives in the
# same repo: it does not reimplement any of it, it just runs the backend
# that is already there, inside the new system.
handoff_gaming() {
  local here setup
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  setup="$here/akari-setup.sh"
  if [[ ! -r $setup ]]; then
    say "akari-setup.sh not found next to the installer — skipping gaming setup"
    return 0
  fi
  say "Running Akari gaming setup inside the new system"
  run mkdir -p /mnt/opt/akari-tool
  run cp -r "$here" /mnt/opt/akari-tool/
  # AKARI_USER lets the backend drop privileges for AUR work.
  arch-chroot /mnt env AKARI_USER="$USERNAME" AKARI_HOME="/home/$USERNAME" \
      /bin/bash /opt/akari-tool/backend/akari-setup.sh apply gaming 2>&1 \
      | tee -a "$LOG" \
    || say "Gaming setup reported errors — the system is still installed and bootable."
}

write_chroot_script() {
  local out=$1 rootdev=$2
  local oldmask; oldmask=$(umask); umask 077
  local uuid; uuid=$(blkid -s UUID -o value "$rootdev")
  [[ -n $uuid ]] || die "could not read the UUID of $rootdev — refusing to write an unbootable boot entry"
  local uc; uc=$(ucode_pkg)
  local rootflags=""
  [[ $FS == btrfs ]] && rootflags=" rootflags=subvol=@"

  # Deliberately not 'set -e' inside: each step reports its own failure so
  # a broken locale does not silently skip the bootloader.
  cat > "$out" <<CHROOT
#!/usr/bin/env bash
set -uo pipefail
fail() { echo "!! \$*" >&2; exit 1; }

# ---- time, locale, console
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime || fail "bad timezone $TIMEZONE"
hwclock --systohc

sed -i "s/^#\\(${LOCALE//./\\.} \\)/\\1/" /etc/locale.gen
grep -q "^${LOCALE}" /etc/locale.gen || echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen || fail "locale-gen failed"
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# ---- identity
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# ---- initramfs
mkinitcpio -P || fail "mkinitcpio failed"

# ---- accounts
echo "root:$ROOTPASS" | chpasswd || fail "could not set the root password"
useradd -m -G wheel -s /bin/bash "$USERNAME" || fail "could not create $USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd || fail "could not set the user password"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

# ---- services
systemctl enable NetworkManager
CHROOT

  # zram
  if [[ $SWAP == zram ]]; then
    cat >> "$out" <<'CHROOT'
cat > /etc/systemd/zram-generator.conf <<'ZRAM'
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
ZRAM
CHROOT
  fi

  # display manager
  case $DESKTOP in
    kde)   echo 'systemctl enable sddm' >> "$out" ;;
    gnome) echo 'systemctl enable gdm'  >> "$out" ;;
    hyprland)
      cat >> "$out" <<'CHROOT'
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml <<'GREET'
[terminal]
vt = 1
[default_session]
command = "tuigreet --time --cmd Hyprland"
user = "greeter"
GREET
systemctl enable greetd
CHROOT
      ;;
  esac

  # multilib early: the gaming hand-off needs it, and it costs nothing.
  cat >> "$out" <<'CHROOT'
sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
pacman -Syu --noconfirm
CHROOT

  # bootloader
  if [[ $BOOTLOADER == systemd-boot ]]; then
    cat >> "$out" <<CHROOT
bootctl --path=/boot install || fail "bootctl install failed"
cat > /boot/loader/loader.conf <<LOADER
default  akari.conf
timeout  3
console-mode max
editor   no
LOADER
cat > /boot/loader/entries/akari.conf <<ENTRY
title   Arch Linux ($KERNEL)
linux   /vmlinuz-$KERNEL
${uc:+initrd  /$uc.img}
initrd  /initramfs-$KERNEL.img
options root=UUID=$uuid rw$rootflags
ENTRY
cat > /boot/loader/entries/akari-fallback.conf <<ENTRY
title   Arch Linux ($KERNEL, fallback initramfs)
linux   /vmlinuz-$KERNEL
${uc:+initrd  /$uc.img}
initrd  /initramfs-$KERNEL-fallback.img
options root=UUID=$uuid rw$rootflags
ENTRY
CHROOT
  else
    if is_uefi; then
      cat >> "$out" <<CHROOT
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch \
  || fail "grub-install failed"
grub-mkconfig -o /boot/grub/grub.cfg || fail "grub-mkconfig failed"
CHROOT
    else
      cat >> "$out" <<CHROOT
grub-install --target=i386-pc "$DISK" || fail "grub-install failed"
grub-mkconfig -o /boot/grub/grub.cfg || fail "grub-mkconfig failed"
CHROOT
    fi
  fi

  # AUR helper, built as the new user
  if [[ $AURHELPER == paru ]]; then
    cat >> "$out" <<CHROOT
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-akari-build
chmod 0440 /etc/sudoers.d/99-akari-build
runuser -u "$USERNAME" -- bash -c '
  cd /tmp && rm -rf paru &&
  git clone --depth 1 https://aur.archlinux.org/paru.git &&
  cd paru && makepkg -si --noconfirm' \
  || echo "!! paru build failed — install it later from akari-tui"
# A paru that cannot start is worse than no paru: say so now, in the log,
# rather than letting the user discover it on first boot.
if ! runuser -u "$USERNAME" -- paru --version >/dev/null 2>&1; then
  echo "!! paru was installed but does not run — remove it with 'pacman -Rns paru'"
fi
rm -f /etc/sudoers.d/99-akari-build
CHROOT
  fi

  echo 'echo ":: chroot configuration complete"' >> "$out"
  umask "$oldmask"
}

# ---------------------------------------------------------------- dispatch

case "${1:-}" in
  --version|-V) echo "akari-install $AKARI_INSTALL_VERSION" ;;
  --help|-h)
    cat <<HELP
akari-install — Arch Linux installer (live ISO only)

  env-check              is this a live ISO, UEFI, online, with a usable disk
  disks                  installable disks, with a reason when one is refused
  detect-tz              best-guess timezone
  sample-config          print a config template
  plan  <config>         exactly what apply would do — writes nothing
  apply <config>         partition, install and configure. DESTRUCTIVE.

apply refuses unless CONFIRM=WIPE is set in the config, the target is not
the live USB, and nothing on it is mounted.

Normally you do not call this directly — run 'akari-install' (the wizard).
HELP
    ;;
  env-check)     cmd_env_check ;;
  disks)         cmd_disks ;;
  detect-tz)     cmd_detect_tz ;;
  sample-config) sample_config ;;
  plan)          cmd_plan "${2:?usage: $0 plan <config>}" ;;
  apply)         cmd_apply "${2:?usage: $0 apply <config>}" ;;
  *) echo "usage: $0 {env-check|disks|detect-tz|sample-config|plan <cfg>|apply <cfg>}"; exit 1 ;;
esac
