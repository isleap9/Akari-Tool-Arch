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

LOGFILE="${XDG_STATE_HOME:-$HOME/.local/state}/akari-tool/changes.log"

# ---------------------------------------------------------------- helpers

log_change() {
  mkdir -p "$(dirname "$LOGFILE")"
  printf '%s | %s\n' "$(date -Is)" "$*" >> "$LOGFILE"
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
    emit root fail "Running as root — run as your user; sudo is used per-command"
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
  local map_count
  map_count=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
  if (( map_count >= 1048576 )); then
    emit tweaks ok "vm.max_map_count = $map_count"
  else
    emit tweaks warn "vm.max_map_count = $map_count (recommend 1048576, as on SteamOS)"
  fi
}

# Steam's search path for custom Proton builds
proton_dir() { echo "${AKARI_COMPAT_DIR:-$HOME/.steam/root/compatibilitytools.d}"; }

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
    echo ":: GRUB detected — regenerating grub.cfg"
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_change "regenerated grub.cfg after kernel install"
  elif command -v bootctl &>/dev/null && sudo bootctl is-installed &>/dev/null; then
    echo ":: systemd-boot detected."
    echo "   NOTE: systemd-boot entries are not auto-generated. If you don't"
    echo "   use kernel-install hooks, add an entry in /boot/loader/entries/"
    echo "   for the new kernel before rebooting into it."
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
    echo ":: Installing $name + ${name}-headers via pacman"
    sudo pacman -S --needed --noconfirm "$name" "${name}-headers"
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
    echo ":: Installing $name + ${name}-headers via $helper (this compiles — can take a long time)"
    "$helper" -S --needed --noconfirm "$name" "${name}-headers"
    log_change "installed kernel via AUR: $name"
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
    echo ":: Installing ${#repo[@]} packages via pacman"
    sudo pacman -S --needed --noconfirm "${repo[@]}"
    log_change "installed selected packages: ${repo[*]}"
  fi
  if ((${#aurp[@]})); then
    local helper=""
    command -v paru &>/dev/null && helper=paru
    [[ -z "$helper" ]] && command -v yay &>/dev/null && helper=yay
    if [[ -n "$helper" ]]; then
      echo ":: Installing ${#aurp[@]} AUR packages via $helper"
      "$helper" -S --needed --noconfirm "${aurp[@]}" || \
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
  sudo cp /etc/pacman.conf /etc/pacman.conf.akari.bak
  sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
  log_change "enabled multilib in /etc/pacman.conf (backup at pacman.conf.akari.bak)"
  echo ":: Syncing package databases"
  sudo pacman -Sy
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
    echo ":: Installing $(wc -l <<<"$missing") packages via pacman"
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $missing
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
      "$helper" -S --needed --noconfirm $missing || \
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
  echo 'vm.max_map_count = 1048576' | sudo tee "$conf" >/dev/null
  sudo sysctl --system >/dev/null
  log_change "wrote $conf (vm.max_map_count=1048576)"

  if is_installed gamemode && ! id -nG "$USER" | grep -qw gamemode; then
    echo ":: Adding $USER to gamemode group (takes effect next login)"
    sudo usermod -aG gamemode "$USER"
    log_change "added $USER to gamemode group"
  fi
  echo ":: Tweaks applied. Changes are logged in $LOGFILE"
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
  if is_installed gamemode && ! id -nG "$USER" | grep -qw gamemode; then
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
    echo ""
    if [[ -d /boot/grub ]]; then
      echo "Bootloader: GRUB — grub.cfg will be regenerated automatically."
    else
      echo "Bootloader: menu update will be attempted; systemd-boot users may"
      echo "need to add a loader entry manually."
    fi
    echo ""
    echo "Your current kernel stays installed. Nothing is removed."
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
  log)      cmd_log ;;
  plan)   case "${2:-gaming}" in
            gaming)   plan_gaming ;;
            multilib) plan_multilib ;;
            tweaks)   plan_tweaks ;;
            kernel)   plan_kernel "${3:-}" ;;
            *) echo "unknown plan target"; exit 1 ;;
          esac ;;
  apply)  case "${2:-}" in
            gaming)   apply_gaming ;;
            multilib) apply_multilib ;;
            tweaks)   apply_tweaks ;;
            kernel)   apply_kernel "${3:-}" ;;
            selected) shift; apply_selected "$@" ;;
            *) echo "usage: $0 apply {gaming|multilib|tweaks|kernel <name>|selected pkg...}"; exit 1 ;;
          esac ;;
  *) echo "usage: $0 {check|packages|kernels|plan gaming|apply {gaming|multilib|tweaks|kernel <name>|selected pkg...}}"; exit 1 ;;
esac
