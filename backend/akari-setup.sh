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

# GPU driver sets (chosen by detect_gpu)
PKGS_GPU_AMD=( mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon )
PKGS_GPU_INTEL=( mesa lib32-mesa vulkan-intel lib32-vulkan-intel )
PKGS_GPU_NVIDIA=( nvidia nvidia-utils lib32-nvidia-utils nvidia-settings )

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
      nvidia) missing=$(missing_from "${PKGS_GPU_NVIDIA[@]}") ;;
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

cmd_check() {
  check_arch
  check_root
  check_network
  check_multilib
  check_gpu
  check_gaming
  check_aur_helper
  check_tweaks
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
      nvidia) m=$(missing_from "${PKGS_GPU_NVIDIA[@]}") ;;
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
      nvidia) pkgs+=( "${PKGS_GPU_NVIDIA[@]}" ) ;;
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

# ---------------------------------------------------------------- dispatch

case "${1:-}" in
  check)  cmd_check ;;
  plan)   case "${2:-gaming}" in gaming) plan_gaming ;; *) echo "unknown plan target"; exit 1 ;; esac ;;
  apply)  case "${2:-}" in
            gaming)   apply_gaming ;;
            multilib) apply_multilib ;;
            tweaks)   apply_tweaks ;;
            *) echo "usage: $0 apply {gaming|multilib|tweaks}"; exit 1 ;;
          esac ;;
  *) echo "usage: $0 {check|plan gaming|apply {gaming|multilib|tweaks}}"; exit 1 ;;
esac
