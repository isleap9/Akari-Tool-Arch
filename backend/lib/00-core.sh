#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---------------------------------------------------------------- privileges
# Two launch modes:
#   CLI:  runs as the user; privileged commands go through sudo.
#   GUI:  the bridge launches applies via pkexec, so we ARE root; the
#         invoking user's identity arrives in AKARI_USER / AKARI_HOME.
RUN_USER="${AKARI_USER:-${USER:-$(id -un)}}"
RUN_HOME="${AKARI_HOME:-${HOME:-/root}}"

run_root() {   # run a command with root privileges
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

run_user() {   # run a command as the real user (AUR helpers refuse root)
  if [[ $EUID -eq 0 && -n "${AKARI_USER:-}" ]]; then
    runuser -u "$AKARI_USER" -- "$@"
  else
    "$@"
  fi
}

# AUR helpers need an interactive terminal (their internal sudo prompts for
# a password). Inside the GUI's pkexec session there is no tty, so paru
# would hang forever. Callers must check this before any AUR operation.
gui_root_no_aur() {
  [[ $EUID -eq 0 && -n "${AKARI_USER:-}" && ! -t 0 ]]
}

# Run an AUR helper as the real user even without a tty.
# We are already root (pkexec), so we grant the user a TEMPORARY sudoers
# rule limited to pacman, run the helper, then remove the rule again.
# This is the same technique used by several distro installers.
run_aur() {   # run_aur <helper> <args...>
  local helper="$1"; shift
  if [[ $EUID -eq 0 && -n "${AKARI_USER:-}" ]]; then
    local drop=/etc/sudoers.d/99-akari-aur-tmp
    printf '%s ALL=(root) NOPASSWD: /usr/bin/pacman\n' "$AKARI_USER" > "$drop"
    chmod 0440 "$drop"
    # shellcheck disable=SC2064
    trap "rm -f '$drop'" RETURN
    local rc=0
    runuser -u "$AKARI_USER" -- "$helper" "$@" || rc=$?
    rm -f "$drop"
    trap - RETURN
    return $rc
  else
    "$helper" "$@"
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

# Extra apps (opt-in via the Gaming page, group "apps"/"apps_aur")
PKGS_APPS_REPO=( obs-studio discord antimicrox )
PKGS_APPS_AUR=( steamtinkerlaunch vesktop-bin )

# Audio: missing lib32 pipewire pieces are the classic "no sound in Proton
# games" cause. Installed by Set up gaming, checked by Diagnose.
PKGS_AUDIO=(
  pipewire pipewire-pulse pipewire-alsa pipewire-jack
  lib32-pipewire lib32-pipewire-jack wireplumber
)

# Controllers: udev rules for gamepads/wheels + user in input group.
PKGS_CONTROLLER=( game-devices-udev )

# Flatpak alternatives — same apps without needing an AUR helper.
# Format: appid|display name
FLATPAK_APPS=(
  "com.heroicgameslauncher.hgl|Heroic Games Launcher"
  "net.davidotek.pupgui2|ProtonUp-Qt"
  "com.usebottles.bottles|Bottles"
)

# Kernels offered by the Kernel page. source: repo (pacman) or aur.
# Format: name|source|description
KERNELS=(
  "linux|repo|Stock Arch kernel"
  "linux-zen|repo|Tuned for desktop responsiveness"
  "linux-lts|repo|Long-term support, most stable"
  "linux-cachyos|cachyos|CachyOS: BORE scheduler & gaming optimizations (prebuilt repo)"
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

