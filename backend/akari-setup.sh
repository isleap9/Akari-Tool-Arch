#!/usr/bin/env bash
#
# akari-setup.sh — Akari Tool Linux backend
# Architecture: check -> plan -> apply. Idempotent. Usable standalone or from the GUI.
#
# Usage:
#   ./akari-setup.sh check            # machine-readable status (used by GUI)
#   ./akari-setup.sh plan gaming      # show what 'apply gaming' would do
#   ./akari-setup.sh apply gaming     # install gaming packages
#   ./akari-setup.sh apply multilib   # enable multilib repo
#   ./akari-setup.sh apply tweaks     # conservative perf tweaks
#
set -euo pipefail

# ---------------------------------------------------------------- privileges
# Two launch modes:
#   CLI:  runs as the user; privileged commands go through sudo.
#   GUI:  the bridge launches applies via pkexec, so we ARE root; the
#         invoking user's identity arrives in AKARI_USER / AKARI_HOME.
RUN_USER="${AKARI_USER:-${USER:-$(id -un)}}"
RUN_HOME="${AKARI_HOME:-${HOME:-/root}}"

run_root() {   # run a command with root privileges
  if [[ $EUID -eq 0 ]]; then "$@"; else run_root "$@"; fi
}

run_user() {   # run a command as the real user (AUR helpers refuse root)
  if [[ $EUID -eq 0 && -n "${AKARI_USER:-}" ]]; then
    runuser -u "$AKARI_USER" -- "$@"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------- data layer
# Package lists live here as data, not logic ("apps as data", CachyOS-style).
# Baseline derived from cachyos-gaming-meta + cachyos-gaming-applications,
# translated to vanilla Arch repos.

PKGS_CORE=(
  steam lutris wine-staging winetricks protontricks umu-launcher
  gamescope mangohud lib32-mangohud gamemode lib32-gamemode vulkan-tools
)

PKGS_DEPS=(
  alsa-plugins lib32-alsa-plugins giflib lib32-giflib glfw
  gst-plugins-base-libs lib32-gtk3 libjpeg-turbo lib32-libjpeg-turbo
  libva lib32-libva mpg123 lib32-mpg123
  opencl-icd-loader lib32-opencl-icd-loader openal lib32-openal libxslt
)

PKGS_FONTS=( ttf-liberation wqy-zenhei )

PKGS_AUR_OPTIONAL=( heroic-games-launcher-bin protonup-qt goverlay )

# Kernels offered by the Kernel page. source: repo (pacman) or aur.
# Format: name|source|description
KERNELS=(
  "linux|repo|Stock Arch kernel"
  "linux-zen|repo|Tuned for desktop responsiveness"
  "linux-lts|repo|Long-term support, most stable"
  "linux-cachyos|aur|CachyOS: BORE scheduler & gaming optimizations"
)

# GPU driver sets (chosen by detect_gpu)
PKGS_GPU_AMD=( mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon )
PKGS_GPU_INTEL=( mesa lib32-mesa vulkan-intel lib32-vulkan-intel )

# NVIDIA kernel-module variants, in detection order. Exactly one should be
# installed; nvidia_kmod_pkg() picks the right one for this system.
NVIDIA_KMOD_VARIANTS=( nvidia-open-dkms nvidia-open nvidia-dkms nvidia )
# Common to every variant:
PKGS_GPU_NVIDIA_COMMON=( nvidia-utils lib32-nvidia-utils nvidia-settings )

# Decide which NVIDIA kernel module package this system should use:
#  1. If a variant is already installed, respect it.
#  2. Otherwise prefer the open modules (required for Turing+ / RTX cards,
#     which is nearly all gaming hardware today):
#       - stock 'linux' kernel only  -> nvidia-open  (prebuilt)
#       - any other kernel installed -> nvidia-open-dkms (builds anywhere)
nvidia_kmod_pkg() {
  local v
  for v in "${NVIDIA_KMOD_VARIANTS[@]}"; do
    is_installed "$v" && { echo "$v"; return; }
  done
  local k nonstock=0
  for k in linux-zen linux-lts linux-hardened linux-rt linux-cachyos; do
    is_installed "$k" && nonstock=1
  done
  if (( nonstock )); then echo nvidia-open-dkms; else echo nvidia-open; fi
}

# Full NVIDIA package set for this system (variant + common + dkms headers)
nvidia_pkgs() {
  local kmod; kmod=$(nvidia_kmod_pkg)
  local pkgs=( "$kmod" "${PKGS_GPU_NVIDIA_COMMON[@]}" )
  if [[ $kmod == *dkms* ]]; then
    # dkms needs headers for every installed kernel
    local k
    for k in linux linux-zen linux-lts linux-hardened linux-rt linux-cachyos; do
      is_installed "$k" && pkgs+=( "${k}-headers" )
    done
  fi
  printf '%s\n' "${pkgs[@]}"
}

LOGFILE="${XDG_STATE_HOME:-$RUN_HOME/.local/state}/akari-tool/changes.log"

# ---------------------------------------------------------------- helpers

log_change() {
  mkdir -p "$(dirname "$LOGFILE")"
  printf '%s | %s\n' "$(date -Is)" "$*" >> "$LOGFILE"
  if [[ $EUID -eq 0 && -n "${AKARI_USER:-}" ]]; then
    chown -R "$AKARI_USER": "$(dirname "$LOGFILE")" 2>/dev/null || true
  fi
}

# Emit machine-readable status lines the GUI parses: KEY|STATE|DETAIL
emit() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }

is_installed() { pacman -Qq "$1" &>/dev/null; }

missing_from() { # echo packages from "$@" that are not installed
  local p
  for p in "$@"; do is_installed "$p" || echo "$p"; done
}

# ---------------------------------------------------------------- checks

check_arch() {
  if grep -q '^ID=arch' /etc/os-release 2>/dev/null; then
    emit arch ok "Arch Linux detected"
  else
    emit arch fail "Not vanilla Arch ($(. /etc/os-release; echo "${PRETTY_NAME:-unknown}"))"
  fi
}

check_root() {
  if [[ $EUID -eq 0 ]]; then
    emit root fail "Running as root — run as your user; run_root is used per-command"
  else
    emit root ok "Running as regular user"
  fi
}

check_network() {
  if curl -sfm 5 -o /dev/null https://archlinux.org; then
    emit network ok "Online"
  else
    emit network warn "No connection to archlinux.org"
  fi
}

check_multilib() {
  # An enabled multilib block = uncommented "[multilib]" line in pacman.conf
  if grep -Eq '^\s*\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    emit multilib ok "multilib repository enabled"
  else
    emit multilib warn "multilib disabled — required for Steam and lib32 packages"
  fi
}

detect_gpu() {
  # VGA/3D/Display controllers
  local pci vendors=""
  pci=$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)
  grep -qi 'nvidia'            <<<"$pci" && vendors+="nvidia "
  grep -qiE 'amd|ati|radeon'   <<<"$pci" && vendors+="amd "
  grep -qi 'intel'             <<<"$pci" && vendors+="intel "
  echo "${vendors:-unknown}"
}

check_gpu() {
  local vendors; vendors=$(detect_gpu)
  local v missing
  if [[ "$vendors" == "unknown" ]]; then
    emit gpu warn "Could not detect GPU vendor"
    return
  fi
  for v in $vendors; do
    case $v in
      amd)    missing=$(missing_from "${PKGS_GPU_AMD[@]}") ;;
      intel)  missing=$(missing_from "${PKGS_GPU_INTEL[@]}") ;;
      nvidia) local npkgs; mapfile -t npkgs < <(nvidia_pkgs)
              missing=$(missing_from "${npkgs[@]}") ;;
    esac
    if [[ -z "$missing" ]]; then
      emit "gpu_$v" ok "$v drivers installed"
    else
      emit "gpu_$v" warn "$v drivers incomplete: $(echo $missing | tr '\n' ' ')"
    fi
  done
}

check_gaming() {
  local all=( "${PKGS_CORE[@]}" "${PKGS_DEPS[@]}" "${PKGS_FONTS[@]}" )
  local missing; missing=$(missing_from "${all[@]}")
  local total=${#all[@]}
  local nmiss=0
  [[ -n "$missing" ]] && nmiss=$(wc -l <<<"$missing")
  emit gaming "$([[ $nmiss -eq 0 ]] && echo ok || echo warn)" \
       "$((total - nmiss))/$total gaming packages installed"
}

check_aur_helper() {
  local h
  for h in paru yay; do
    if command -v "$h" &>/dev/null; then
      emit aur ok "AUR helper found: $h"
      return
    fi
  done
  emit aur warn "No AUR helper — optional packages (Heroic, ProtonUp-Qt) will be skipped"
}

check_tweaks() {
  local map_count issues=""
  map_count=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
  (( map_count < 1048576 )) && issues+="vm.max_map_count=$map_count (want 1048576); "
  if is_installed gamemode && ! id -nG "$RUN_USER" 2>/dev/null | grep -qw gamemode; then
    issues+="$RUN_USER not in gamemode group; "
  fi
  if [[ -z "$issues" ]]; then
    emit tweaks ok "vm.max_map_count = $map_count, gamemode group OK"
  else
    emit tweaks warn "${issues%; }"
  fi
}

# Steam's search path for custom Proton builds
proton_dir() { echo "${AKARI_COMPAT_DIR:-$RUN_HOME/.steam/root/compatibilitytools.d}"; }

# Newest installed GE-Proton version, or empty
proton_installed_version() {
  local d
  d=$(ls -d "$(proton_dir)"/GE-Proton* 2>/dev/null | sort -V | tail -1) || true
  [[ -n "$d" ]] && basename "$d"
  return 0   # empty result is not an error (set -e safety)
}

check_proton() {
  local v; v=$(proton_installed_version)
  if [[ -n "$v" ]]; then
    emit proton ok "$v installed"
  elif is_installed protonup-qt; then
    emit proton warn "No custom Proton yet — open ProtonUp-Qt to install GE-Proton"
  else
    emit proton warn "Proton-GE not installed (Steam's built-in Proton still works)"
  fi
}

check_staleness() {
  local last epoch_now epoch_last days
  last=$(grep -F 'starting full system upgrade' /var/log/pacman.log 2>/dev/null \
         | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/') || true
  if [[ -z "$last" ]]; then
    emit sysupdate warn "No full system upgrade found in pacman.log"
    return
  fi
  epoch_now=$(date +%s); epoch_last=$(date -d "$last" +%s 2>/dev/null || echo 0)
  days=$(( (epoch_now - epoch_last) / 86400 ))
  if (( days <= 14 )); then
    emit sysupdate ok "Last full upgrade: $days day(s) ago"
  else
    emit sysupdate warn "Last full upgrade: $days days ago — installing packages on a stale system risks breakage"
  fi
}

cmd_check() {
  check_arch
  check_root
  check_network
  check_multilib
  check_gpu
  check_gaming
  check_proton
  check_aur_helper
  check_tweaks
  check_staleness
}

# Emit every known package with group + install state: PKG|group|name|1/0
# Used by the GUI's Gaming page.
cmd_packages() {
  local p
  for p in "${PKGS_CORE[@]}";  do emit_pkg core  "$p"; done
  for p in "${PKGS_DEPS[@]}";  do emit_pkg deps  "$p"; done
  for p in "${PKGS_FONTS[@]}"; do emit_pkg fonts "$p"; done
  local vendors v
  vendors=$(detect_gpu)
  for v in $vendors; do
    case $v in
      amd)    for p in "${PKGS_GPU_AMD[@]}";    do emit_pkg gpu "$p"; done ;;
      intel)  for p in "${PKGS_GPU_INTEL[@]}";  do emit_pkg gpu "$p"; done ;;
      nvidia) local npkgs; mapfile -t npkgs < <(nvidia_pkgs)
              for p in "${npkgs[@]}";           do emit_pkg gpu "$p"; done ;;
    esac
  done
  if command -v paru &>/dev/null || command -v yay &>/dev/null; then
    for p in "${PKGS_AUR_OPTIONAL[@]}"; do emit_pkg aur "$p"; done
  fi
}

emit_pkg() {
  printf 'PKG|%s|%s|%d\n' "$1" "$2" "$(is_installed "$2" && echo 1 || echo 0)"
}

# ---- UKI-aware boot handling ------------------------------------------
# Systems like EFI-with-unified-kernel-images build the kernel+initramfs
# into one signed .efi (see the stock preset's default_uki=). A new kernel
# installed the classic way is INVISIBLE to such a boot chain until its
# preset is converted to the same style. Learned the hard way.

STOCK_PRESET=/etc/mkinitcpio.d/linux.preset

stock_uki_path() {
  grep -E '^default_uki=' "$STOCK_PRESET" 2>/dev/null | cut -d'"' -f2 || true
}

boot_uses_uki() { [[ -n "$(stock_uki_path)" ]]; }

# Convert a kernel's preset to UKI style, cloning the stock preset's
# pattern (same ESP directory, same options), then rebuild.
setup_uki_preset() {
  local name="$1"
  local preset="/etc/mkinitcpio.d/${name}.preset"
  [[ -f "$preset" ]] || { echo ":: No preset for $name — skipping UKI setup." >&2; return 1; }

  if grep -Eq '^default_uki=' "$preset"; then
    echo ":: $name preset is already UKI-style."
  else
    local dir target
    dir=$(dirname "$(stock_uki_path)")           # e.g. /boot/EFI/Linux
    target="$dir/arch-${name}.efi"
    echo ":: Converting $preset to UKI style (target: $target)"
    run_root cp "$preset" "${preset}.akari.bak"
    run_root sed -i 's|^default_image=|#default_image=|' "$preset"
    if grep -Eq '^#default_uki=' "$preset"; then
      run_root sed -i "s|^#default_uki=.*|default_uki=\"$target\"|" "$preset"
    else
      echo "default_uki=\"$target\"" | run_root tee -a "$preset" >/dev/null
    fi
    # carry the stock preset's default_options (splash etc.) if ours is inactive
    local opts
    opts=$(grep -E '^default_options=' "$STOCK_PRESET" || true)
    if [[ -n "$opts" ]] && ! grep -Eq '^default_options=' "$preset"; then
      if grep -Eq '^#default_options=' "$preset"; then
        run_root sed -i "s|^#default_options=.*|$opts|" "$preset"
      else
        echo "$opts" | run_root tee -a "$preset" >/dev/null
      fi
    fi
    log_change "converted $preset to UKI style ($target); backup: ${preset}.akari.bak"
  fi

  echo ":: Building unified kernel image for $name"
  run_root mkinitcpio -p "$name"
  if command -v sbctl &>/dev/null; then
    echo ":: sbctl present — the post hook signs the UKI for Secure Boot automatically."
  fi
  # the classic initramfs from the package install is now dead weight
  local leftover="/boot/initramfs-${name}.img"
  if [[ -f "$leftover" ]]; then
    echo ":: Removing now-redundant classic initramfs: $leftover"
    run_root rm -f "$leftover"
    log_change "removed redundant initramfs after UKI conversion: $leftover"
  fi
}

snapper_note() {
  if command -v snapper &>/dev/null; then
    echo ":: snapper detected — pre/post snapshots are taken automatically."
  fi
  return 0
}

# Kernel currently booted, mapped to its package name
running_kernel() {
  local r; r=$(uname -r)
  case "$r" in
    *cachyos*)  echo linux-cachyos ;;
    *zen*)      echo linux-zen ;;
    *lts*)      echo linux-lts ;;
    *hardened*) echo linux-hardened ;;
    *)          echo linux ;;
  esac
}

# Emit kernel list: KRN|name|source|description|installed|running
cmd_kernels() {
  local entry name source desc run
  run=$(running_kernel)
  for entry in "${KERNELS[@]}"; do
    IFS='|' read -r name source desc <<<"$entry"
    printf 'KRN|%s|%s|%s|%d|%d\n' "$name" "$source" "$desc" \
      "$(is_installed "$name" && echo 1 || echo 0)" \
      "$([[ $name == "$run" ]] && echo 1 || echo 0)"
  done
}

# Update the bootloader menu so a newly installed kernel is bootable.
update_bootloader() {
  if [[ -d /boot/grub ]]; then
    if [[ -x /etc/grub.d/15_uki ]] && boot_uses_uki; then
      echo ":: GRUB with dynamic UKI menu (15_uki) — new UKIs in the ESP are"
      echo "   discovered automatically at boot. Note: auto-entries share the"
      echo "   same 'Arch Linux' label; named entries can be added in 40_custom."
    fi
    echo ":: Regenerating grub.cfg"
    run_root grub-mkconfig -o /boot/grub/grub.cfg
    log_change "regenerated grub.cfg after kernel change"
    if boot_uses_uki && [[ ! -x /etc/grub.d/15_uki ]] \
       && ! run_root grep -q "arch-.*\.efi" /etc/grub.d/40_custom 2>/dev/null; then
      echo ":: WARNING: this system boots UKIs but neither the dynamic UKI menu"
      echo "   (15_uki) nor a custom entry seems active. Add a chainloader entry"
      echo "   for the new UKI in /etc/grub.d/40_custom and regenerate grub.cfg."
    fi
  elif command -v bootctl &>/dev/null && run_root bootctl is-installed &>/dev/null; then
    if boot_uses_uki; then
      echo ":: systemd-boot detected — UKIs in EFI/Linux/ are auto-discovered."
    else
      echo ":: systemd-boot detected."
      echo "   NOTE: entries are not auto-generated. If you don't use"
      echo "   kernel-install hooks, add one in /boot/loader/entries/."
    fi
  else
    echo ":: Could not identify bootloader — update its menu manually if needed."
  fi
}

# Install a kernel (+ headers) alongside the current one. NEVER removes
# the running kernel — the user picks the new one from the boot menu.
apply_kernel() {
  local name="${1:-}"
  local entry n s found="" source=""
  for entry in "${KERNELS[@]}"; do
    IFS='|' read -r n s _ <<<"$entry"
    [[ $n == "$name" ]] && { found=$n; source=$s; }
  done
  [[ -z "$found" ]] && { echo "Unknown kernel: $name" >&2; return 1; }

  if is_installed "$name"; then
    echo ":: $name is already installed."
  elif [[ $source == repo ]]; then
    snapper_note
    echo ":: Installing $name + ${name}-headers via pacman"
    run_root pacman -S --needed --noconfirm "$name" "${name}-headers"
    log_change "installed kernel: $name"
  else
    local helper=""
    command -v paru &>/dev/null && helper=paru
    [[ -z "$helper" ]] && command -v yay &>/dev/null && helper=yay
    if [[ -z "$helper" ]]; then
      echo ":: $name comes from the AUR and no AUR helper was found." >&2
      echo "   Install paru or yay first, or use the CachyOS repos." >&2
      return 1
    fi
    snapper_note
    echo ":: Installing $name + ${name}-headers via $helper (this compiles — can take a long time)"
    run_user "$helper" -S --needed --noconfirm "$name" "${name}-headers"
    log_change "installed kernel via AUR: $name"
  fi

  # UKI-style boot chain? The kernel is invisible until its preset matches.
  if boot_uses_uki; then
    setup_uki_preset "$name"
  fi

  update_bootloader

  echo ":: Done. '$name' was installed ALONGSIDE your current kernel —"
  echo "   nothing was removed. Select it in the boot menu on next reboot."
  echo "   (dkms drivers like nvidia-open-dkms rebuild for it automatically.)"
}

# Install an explicit, user-selected package list. AUR-group packages go
# through the helper; everything else through pacman.
apply_selected() {
  shift  # drop the 'selected' target word
  [[ $# -eq 0 ]] && { echo "Nothing selected."; return 0; }

  grep -Eq '^\s*\[multilib\]' /etc/pacman.conf 2>/dev/null || apply_multilib

  local repo=() aurp=() p known_aur=" ${PKGS_AUR_OPTIONAL[*]} "
  for p in "$@"; do
    if [[ $known_aur == *" $p "* ]]; then aurp+=("$p"); else repo+=("$p"); fi
  done

  if ((${#repo[@]})); then
    snapper_note
    echo ":: Installing ${#repo[@]} packages via pacman"
    run_root pacman -S --needed --noconfirm "${repo[@]}"
    log_change "installed selected packages: ${repo[*]}"
  fi
  if ((${#aurp[@]})); then
    local helper=""
    command -v paru &>/dev/null && helper=paru
    [[ -z "$helper" ]] && command -v yay &>/dev/null && helper=yay
    if [[ -n "$helper" ]]; then
      echo ":: Installing ${#aurp[@]} AUR packages via $helper"
      run_user "$helper" -S --needed --noconfirm "${aurp[@]}" || \
        echo ":: (AUR install failed — continuing)"
      log_change "installed selected AUR packages: ${aurp[*]}"
    else
      echo ":: No AUR helper — skipped: ${aurp[*]}"
    fi
  fi
  echo ":: Selected install complete."
}

# ---------------------------------------------------------------- plan/apply

plan_gaming() {
  local vendors v
  vendors=$(detect_gpu)
  echo "== Plan: gaming setup =="
  local m; m=$(missing_from "${PKGS_CORE[@]}" "${PKGS_DEPS[@]}" "${PKGS_FONTS[@]}")
  if [[ -z "$m" ]]; then echo "All repo packages already installed."; else
    echo "Will install (pacman):"; echo "$m" | sed 's/^/  /'
  fi
  for v in $vendors; do
    case $v in
      amd)    m=$(missing_from "${PKGS_GPU_AMD[@]}") ;;
      intel)  m=$(missing_from "${PKGS_GPU_INTEL[@]}") ;;
      nvidia) local npkgs; mapfile -t npkgs < <(nvidia_pkgs)
              m=$(missing_from "${npkgs[@]}") ;;
      *)      continue ;;
    esac
    [[ -n "$m" ]] && { echo "GPU ($v) drivers to install:"; echo "$m" | sed 's/^/  /'; }
  done
  if command -v paru &>/dev/null || command -v yay &>/dev/null; then
    m=$(missing_from "${PKGS_AUR_OPTIONAL[@]}")
    [[ -n "$m" ]] && { echo "Optional (AUR):"; echo "$m" | sed 's/^/  /'; }
  fi
}

apply_multilib() {
  if grep -Eq '^\s*\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    echo "multilib already enabled."; return 0
  fi
  echo ":: Enabling multilib in /etc/pacman.conf (backup: pacman.conf.akari.bak)"
  run_root cp /etc/pacman.conf /etc/pacman.conf.akari.bak
  run_root sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
  log_change "enabled multilib in /etc/pacman.conf (backup at pacman.conf.akari.bak)"
  echo ":: Syncing package databases"
  run_root pacman -Sy
}

apply_gaming() {
  # multilib is a hard prerequisite
  grep -Eq '^\s*\[multilib\]' /etc/pacman.conf 2>/dev/null || apply_multilib

  local vendors v pkgs=( "${PKGS_CORE[@]}" "${PKGS_DEPS[@]}" "${PKGS_FONTS[@]}" )
  vendors=$(detect_gpu)
  for v in $vendors; do
    case $v in
      amd)    pkgs+=( "${PKGS_GPU_AMD[@]}" ) ;;
      intel)  pkgs+=( "${PKGS_GPU_INTEL[@]}" ) ;;
      nvidia) local npkgs; mapfile -t npkgs < <(nvidia_pkgs)
              pkgs+=( "${npkgs[@]}" ) ;;
    esac
  done

  local missing; missing=$(missing_from "${pkgs[@]}")
  if [[ -z "$missing" ]]; then
    echo ":: All gaming packages already installed."
  else
    snapper_note
    echo ":: Installing $(wc -l <<<"$missing") packages via pacman"
    # shellcheck disable=SC2086
    run_root pacman -S --needed --noconfirm $missing
    log_change "installed gaming packages: $(echo $missing | tr '\n' ' ')"
  fi

  # Optional AUR extras — never a hard dependency
  local helper=""
  command -v paru &>/dev/null && helper=paru
  [[ -z "$helper" ]] && command -v yay &>/dev/null && helper=yay
  if [[ -n "$helper" ]]; then
    missing=$(missing_from "${PKGS_AUR_OPTIONAL[@]}")
    if [[ -n "$missing" ]]; then
      echo ":: Installing optional AUR packages via $helper"
      # shellcheck disable=SC2086
      run_user "$helper" -S --needed --noconfirm $missing || \
        echo ":: (AUR extras failed — continuing, they are optional)"
      log_change "installed AUR extras: $(echo $missing | tr '\n' ' ')"
    fi
  else
    echo ":: No AUR helper found — skipping optional extras (Heroic, ProtonUp-Qt, GOverlay)"
  fi

  echo ":: Gaming setup complete."
}

apply_tweaks() {
  local conf=/etc/sysctl.d/80-akari-gaming.conf
  echo ":: Setting vm.max_map_count = 1048576 ($conf)"
  echo 'vm.max_map_count = 1048576' | run_root tee "$conf" >/dev/null
  run_root sysctl --system >/dev/null
  log_change "wrote $conf (vm.max_map_count=1048576)"

  if is_installed gamemode && ! id -nG "$RUN_USER" | grep -qw gamemode; then
    echo ":: Adding $RUN_USER to gamemode group (takes effect next login)"
    run_root usermod -aG gamemode "$RUN_USER"
    log_change "added $RUN_USER to gamemode group"
  fi
  echo ":: Tweaks applied. Changes are logged in $LOGFILE"
}

plan_sysupdate() {
  echo "== Plan: full system upgrade =="
  echo "Will run: pacman -Syu (all packages updated to current)"
  snapper_note
  return 0
}

apply_sysupdate() {
  snapper_note
  echo ":: Running full system upgrade (pacman -Syu)"
  run_root pacman -Syu --noconfirm
  log_change "ran full system upgrade (pacman -Syu)"
  echo ":: System upgrade complete."
}

plan_all() {
  plan_gaming
  echo ""
  plan_tweaks
  echo ""
  echo "These run back to back — one confirmation, full setup."
}

apply_all() {
  apply_gaming
  echo ""
  apply_tweaks
  echo ""
  echo ":: Full setup complete. Run Diagnose to verify everything works."
}

plan_multilib() {
  echo "== Plan: enable multilib =="
  if grep -Eq '^\s*\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    echo "multilib is already enabled — nothing to do."
  else
    echo "Will do:"
    echo "  1. Back up /etc/pacman.conf to /etc/pacman.conf.akari.bak"
    echo "  2. Uncomment the [multilib] block"
    echo "  3. Run 'pacman -Sy' to sync the new repository"
  fi
}

plan_tweaks() {
  echo "== Plan: performance tweaks =="
  echo "Will do:"
  echo "  1. Write /etc/sysctl.d/80-akari-gaming.conf"
  echo "     (vm.max_map_count = 1048576 — same value SteamOS ships)"
  echo "  2. Reload sysctl settings"
  if is_installed gamemode && ! id -nG "$RUN_USER" | grep -qw gamemode; then
    echo "  3. Add $USER to the 'gamemode' group (takes effect next login)"
  fi
  echo "All changes are logged and reversible."
}

plan_kernel() {
  local name="${1:-}"
  local entry n s d found="" source="" desc=""
  for entry in "${KERNELS[@]}"; do
    IFS='|' read -r n s d <<<"$entry"
    [[ $n == "$name" ]] && { found=$n; source=$s; desc=$d; }
  done
  [[ -z "$found" ]] && { echo "Unknown kernel: $name"; return 1; }

  echo "== Plan: install $name =="
  echo "$desc"
  echo ""
  if is_installed "$name"; then
    echo "$name is already installed — only the bootloader menu will be refreshed."
  else
    if [[ $source == repo ]]; then
      echo "Will install via pacman:  $name  ${name}-headers"
    else
      echo "Will build & install via AUR helper:  $name  ${name}-headers"
      echo "(compiling a kernel — expect a long build time)"
    fi
    if boot_uses_uki; then
      local dir; dir=$(dirname "$(stock_uki_path)")
      echo ""
      echo "This system boots unified kernel images (UKIs). Will also:"
      echo "  - convert the $name preset to UKI style (backup kept)"
      echo "  - build $dir/arch-${name}.efi via mkinitcpio"
      command -v sbctl &>/dev/null && \
      echo "  - sbctl signs it automatically (Secure Boot)"
    fi
    echo ""
    if [[ -d /boot/grub ]]; then
      if [[ -x /etc/grub.d/15_uki ]] && boot_uses_uki; then
        echo "Bootloader: GRUB with dynamic UKI menu — the new kernel appears"
        echo "automatically (entries share the generic 'Arch Linux' label)."
      else
        echo "Bootloader: GRUB — grub.cfg will be regenerated automatically."
      fi
    else
      echo "Bootloader: menu update will be attempted; systemd-boot users may"
      echo "need to add a loader entry manually."
    fi
    command -v snapper &>/dev/null && \
    echo "snapper: pre/post snapshots are taken automatically."
    echo ""
    echo "Your current kernel stays installed. Nothing is removed."
  fi
}

plan_remove_kernel() {
  local name="${1:-}"
  echo "== Plan: remove $name =="
  if [[ $name == linux ]]; then
    echo "Refusing: the stock 'linux' kernel is kept as a fallback."
    return 1
  fi
  if [[ $name == "$(running_kernel)" ]]; then
    echo "Refusing: $name is the kernel you are booted into right now."
    echo "Reboot into another kernel first, then remove this one."
    return 1
  fi
  if ! is_installed "$name"; then
    echo "$name is not installed — nothing to do."
    return 0
  fi
  echo "Will do:"
  echo "  1. Remove packages: $name $(is_installed "${name}-headers" && echo "${name}-headers")"
  local uki
  uki=$(grep -E '^default_uki=' "/etc/mkinitcpio.d/${name}.preset" 2>/dev/null | cut -d'"' -f2) || true
  [[ -n "$uki" ]] && echo "  2. Delete its unified kernel image: $uki"
  echo "  3. Remove leftover initramfs files, refresh the bootloader menu"
  echo ""
  echo "If you added a custom GRUB entry for it (40_custom), remove that"
  echo "entry manually afterwards — it will otherwise point at a missing file."
}

# Remove a kernel package + its boot artifacts. Guarded: never the running
# kernel, never stock 'linux'.
remove_kernel() {
  local name="${1:-}"
  [[ -z "$name" ]] && { echo "usage: apply remove-kernel <name>" >&2; return 1; }
  if [[ $name == linux ]]; then
    echo ":: Refusing to remove the stock 'linux' kernel (kept as fallback)." >&2
    return 1
  fi
  if [[ $name == "$(running_kernel)" ]]; then
    echo ":: Refusing: $name is currently running. Boot another kernel first." >&2
    return 1
  fi
  if ! is_installed "$name"; then
    echo ":: $name is not installed."
    return 0
  fi

  # Capture the UKI path from the preset BEFORE pacman deletes the preset
  local uki=""
  uki=$(grep -E '^default_uki=' "/etc/mkinitcpio.d/${name}.preset" 2>/dev/null | cut -d'"' -f2) || true

  local pkgs=( "$name" )
  is_installed "${name}-headers" && pkgs+=( "${name}-headers" )
  echo ":: Removing ${pkgs[*]}"
  run_root pacman -Rns --noconfirm "${pkgs[@]}"
  log_change "removed kernel: ${pkgs[*]}"

  # Boot artifacts pacman doesn't own
  if [[ -n "$uki" && -f "$uki" ]]; then
    echo ":: Deleting unified kernel image: $uki"
    run_root rm -f "$uki"
    log_change "deleted UKI: $uki"
  fi
  local leftover="/boot/initramfs-${name}.img"
  if [[ -f "$leftover" ]]; then
    echo ":: Deleting leftover initramfs: $leftover"
    run_root rm -f "$leftover"
    log_change "deleted leftover initramfs: $leftover"
  fi

  update_bootloader
  echo ":: $name removed. If a custom GRUB entry (40_custom) referenced it,"
  echo "   edit /etc/grub.d/40_custom and regenerate grub.cfg."
}

# ---- functional diagnosis ----------------------------------------------
# Unlike 'check' (package presence), these tests exercise the actual
# gaming stack: does Vulkan respond, in both bitnesses, on the right GPU.
# Emits: DIA|key|state|title|detail|fix   (fields sanitized of pipes)

run_diag() {
  printf 'DIA|%s|%s|%s|%s|%s\n' "$1" "$2" \
    "$(tr -d '|' <<<"$3")" "$(tr -d '|' <<<"$4")" "$(tr -d '|' <<<"$5")"
}

cmd_diagnose() {
  local vendors; vendors=$(detect_gpu)

  # -- 64-bit Vulkan: does it respond, and with which devices? ----------
  local devs=""
  if ! command -v vulkaninfo &>/dev/null; then
    run_diag vk64 warn "Vulkan (64-bit)" \
      "vulkaninfo not found — cannot test" \
      "Install vulkan-tools (included in Set up gaming)"
  else
    devs=$(vulkaninfo --summary 2>/dev/null \
           | grep -E 'deviceName' | sed 's/.*= *//' | sort -u \
           | paste -sd ', ' -) || true
    if [[ -n "$devs" ]]; then
      run_diag vk64 ok "Vulkan (64-bit)" "Responding. Devices: $devs" ""
    else
      run_diag vk64 fail "Vulkan (64-bit)" \
        "No Vulkan devices respond — games will not run" \
        "Check the GPU Drivers card on Overview"
    fi
  fi

  # -- Discrete GPU actually visible to Vulkan? --------------------------
  # Desktop trap: monitor plugged into the motherboard, or broken driver,
  # and everything silently renders on the iGPU.
  if [[ "$vendors" == *nvidia* && -n "$devs" ]]; then
    if grep -qiE 'nvidia|geforce|rtx|gtx' <<<"$devs"; then
      run_diag dgpu ok "Discrete GPU (NVIDIA)" \
        "Your NVIDIA card is visible to Vulkan" ""
    else
      run_diag dgpu fail "Discrete GPU (NVIDIA)" \
        "An NVIDIA GPU is in this system but Vulkan cannot see it" \
        "Driver problem or module not loaded — check GPU Drivers, then reboot"
    fi
  fi

  # -- 32-bit Vulkan (what older Windows games via Proton need) ----------
  if [[ ! -e /usr/lib32/libvulkan.so.1 ]]; then
    run_diag vk32 fail "Vulkan (32-bit)" \
      "lib32 Vulkan loader missing — 32-bit games can't render" \
      "Run Set up gaming (installs lib32 packages)"
  else
    local miss32=""
    [[ "$vendors" == *nvidia* && ! -e /usr/lib32/libGLX_nvidia.so.0 ]] && miss32+="lib32-nvidia-utils "
    [[ "$vendors" == *amd*    && ! -e /usr/lib32/libvulkan_radeon.so ]] && miss32+="lib32-vulkan-radeon "
    [[ "$vendors" == *intel*  && ! -e /usr/lib32/libvulkan_intel.so  ]] && miss32+="lib32-vulkan-intel "
    if [[ -z "$miss32" ]]; then
      run_diag vk32 ok "Vulkan (32-bit)" \
        "32-bit loader and GPU drivers present" ""
    else
      run_diag vk32 fail "Vulkan (32-bit)" \
        "32-bit driver missing: $miss32— 32-bit games fall back or fail" \
        "Install from the Gaming page (GPU drivers group)"
    fi
  fi

  # -- gamemode daemon ----------------------------------------------------
  if ! command -v gamemoded &>/dev/null; then
    run_diag gamemode warn "GameMode" \
      "gamemode not installed" \
      "Included in Set up gaming"
  else
    local gm
    gm=$(gamemoded -s 2>&1) || true
    if grep -qi 'is active' <<<"$gm"; then
      run_diag gamemode ok "GameMode" "Daemon reachable — currently active" ""
    elif grep -qi 'is inactive' <<<"$gm"; then
      run_diag gamemode ok "GameMode" \
        "Daemon reachable (inactive — activates when a game requests it)" ""
    else
      run_diag gamemode warn "GameMode" \
        "gamemoded did not respond: $gm" \
        "Log out/in if you were just added to the gamemode group"
    fi
    if ! id -nG "$RUN_USER" 2>/dev/null | grep -qw gamemode; then
      run_diag gamemode_grp warn "GameMode group" \
        "$USER is not in the gamemode group" \
        "Apply tweaks on Overview, then log out and back in"
    fi
  fi

  # -- gamescope & umu ----------------------------------------------------
  if command -v gamescope &>/dev/null; then
    local gsv
    gsv=$(gamescope --version 2>&1 | head -1 | sed 's/\x1b\[[0-9;]*m//g' | tr -cd '[:print:]' | head -c 40)
    run_diag gamescope ok "Gamescope" "Installed ($gsv)" ""
  else
    run_diag gamescope warn "Gamescope" "Not installed" "Included in Set up gaming"
  fi
  if command -v umu-run &>/dev/null; then
    run_diag umu ok "umu launcher" "Installed — Lutris/Heroic can use Proton" ""
  else
    run_diag umu warn "umu launcher" "Not installed" "Included in Set up gaming"
  fi

  # -- Steam libraries on NTFS (classic Proton breaker) -------------------
  local ntfs_mounts m bad=""
  ntfs_mounts=$(findmnt -rn -t ntfs,ntfs3 -o TARGET 2>/dev/null | paste -sd ' ' -) || true
  if [[ -z "$ntfs_mounts" ]]; then
    run_diag ntfs ok "NTFS drives" "No NTFS partitions mounted" ""
  else
    for m in $ntfs_mounts; do
      if find "$m" -maxdepth 3 -type d -name steamapps -print -quit 2>/dev/null | grep -q .; then
        bad+="$m "
      fi
    done
    if [[ -n "$bad" ]]; then
      run_diag ntfs fail "Steam library on NTFS" \
        "steamapps found on NTFS mount(s): $bad— Proton games break on NTFS" \
        "Move the library to an ext4/btrfs drive (recommended)"
    else
      run_diag ntfs warn "NTFS drives" \
        "NTFS mounted at: $ntfs_mounts — fine for storage, do not put Steam libraries there" ""
    fi
  fi

  # -- Game controllers ----------------------------------------------------
  local pads
  pads=$(grep -iE '^N: Name=.*(controller|gamepad|dualsense|dualshock|x-box|xbox|joy-con|pro controller|8bitdo|wireless controller)' \
         /proc/bus/input/devices 2>/dev/null \
         | sed -E 's/^N: Name="(.*)"/\1/' | sort -u | paste -sd ', ' -) || true
  if [[ -n "$pads" ]]; then
    run_diag pads ok "Controllers detected" "$pads" ""
    # permissions layer for non-Xbox pads + Steam Input
    if is_installed game-devices-udev; then
      run_diag pads_udev ok "Controller udev rules" "game-devices-udev installed" ""
    else
      run_diag pads_udev warn "Controller udev rules" \
        "game-devices-udev not installed — PlayStation/Switch/8BitDo pads may lack permissions" \
        "Install game-devices-udev (AUR), then replug the controller"
    fi
    if [[ -e /dev/uinput ]]; then
      run_diag pads_uinput ok "uinput device" "Present (Steam Input can remap)" ""
    else
      run_diag pads_uinput warn "uinput device" \
        "/dev/uinput missing — Steam Input remapping unavailable" \
        "modprobe uinput, or install game-devices-udev"
    fi
  else
    run_diag pads ok "Controllers" "None connected right now (plug one in and re-run to test)" ""
  fi

  # -- Hyprland gaming settings (only when running under Hyprland) --------
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl &>/dev/null; then
    local tearing vrr
    tearing=$(hyprctl getoption general:allow_tearing 2>/dev/null | grep -oE 'int: [01]' | grep -oE '[01]$') || true
    vrr=$(hyprctl getoption misc:vrr 2>/dev/null | grep -oE 'int: [0-9]' | grep -oE '[0-9]$') || true
    if [[ "$tearing" == "1" ]]; then
      run_diag hypr_tear ok "Hyprland: tearing" \
        "allow_tearing enabled — fullscreen games can bypass vsync latency" ""
    else
      run_diag hypr_tear warn "Hyprland: tearing" \
        "allow_tearing is off — lower-latency fullscreen gaming unavailable" \
        "Set general:allow_tearing = true plus an immediate windowrule for games"
    fi
    case "$vrr" in
      1|2) run_diag hypr_vrr ok "Hyprland: VRR" "vrr = $vrr (adaptive sync active)" "" ;;
      0)   run_diag hypr_vrr warn "Hyprland: VRR" \
             "vrr = 0 — adaptive sync disabled" \
             "Set misc:vrr = 1 (always) or 2 (fullscreen only) if your monitor supports it" ;;
      *)   : ;;  # hyprctl unavailable mid-session; skip silently
    esac
  fi
}

cmd_log() {
  if [[ -s "$LOGFILE" ]]; then
    cat "$LOGFILE"
  else
    echo "No changes recorded yet."
    echo "Every change Akari Tool makes to this system will be listed here."
  fi
}

# ---------------------------------------------------------------- dispatch

case "${1:-}" in
  check)    cmd_check ;;
  packages) cmd_packages ;;
  kernels)  cmd_kernels ;;
  diagnose) cmd_diagnose ;;
  log)      cmd_log ;;
  plan)   case "${2:-gaming}" in
            gaming)        plan_gaming ;;
            multilib)      plan_multilib ;;
            tweaks)        plan_tweaks ;;
            kernel)        plan_kernel "${3:-}" ;;
            remove-kernel) plan_remove_kernel "${3:-}" ;;
            sysupdate)     plan_sysupdate ;;
            all)           plan_all ;;
            *) echo "unknown plan target"; exit 1 ;;
          esac ;;
  apply)  case "${2:-}" in
            gaming)        apply_gaming ;;
            multilib)      apply_multilib ;;
            tweaks)        apply_tweaks ;;
            kernel)        apply_kernel "${3:-}" ;;
            remove-kernel) remove_kernel "${3:-}" ;;
            sysupdate)     apply_sysupdate ;;
            all)           apply_all ;;
            selected)      shift; apply_selected "$@" ;;
            *) echo "usage: $0 apply {gaming|multilib|tweaks|kernel <name>|remove-kernel <name>|selected pkg...}"; exit 1 ;;
          esac ;;
  *) echo "usage: $0 {check|packages|kernels|plan gaming|apply {gaming|multilib|tweaks|kernel <name>|selected pkg...}}"; exit 1 ;;
esac
