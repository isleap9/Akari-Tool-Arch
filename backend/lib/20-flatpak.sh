#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- flatpak track -----------------------------------------------------
flatpak_ready() {
  command -v flatpak &>/dev/null && \
    flatpak remotes 2>/dev/null | grep -qiw flathub
}

flatpak_installed() {   # flatpak_installed <appid>
  flatpak list --app --columns=application 2>/dev/null | grep -qxF "$1"
}

plan_flatpak_setup() {
  echo "== Plan: set up Flatpak =="
  if flatpak_ready; then
    echo "Flatpak + Flathub already set up — nothing to do."
  else
    echo "Will do:"
    is_installed flatpak || echo "  - pacman -S flatpak"
    echo "  - add the Flathub remote (flathub.org)"
    echo "Afterwards Heroic, ProtonUp-Qt and Bottles can be installed as Flatpaks"
    echo "— no AUR helper needed. (A relogin may be needed for menu entries.)"
  fi
}

apply_flatpak_setup() {
  if flatpak_ready; then echo ":: Flatpak + Flathub already set up."; return 0; fi
  is_installed flatpak || {
    echo ":: Installing flatpak"
    run_root pacman -S --needed --noconfirm flatpak
  }
  echo ":: Adding Flathub remote"
  run_root flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  log_change "set up flatpak with Flathub remote"
  echo ":: Flatpak ready. Flatpak apps now appear on the Gaming page."
  echo "   (Log out and back in once so app menu entries show up.)"
}

apply_flatpak() {   # apply_flatpak <appid...>
  [[ $# -eq 0 ]] && { echo "No Flatpak apps given."; return 0; }
  flatpak_ready || apply_flatpak_setup
  echo ":: Installing ${#} Flatpak app(s) from Flathub"
  # system-wide install; runs fine as root (GUI) or via sudo-less user +
  # polkit (CLI). --noninteractive answers all prompts.
  run_root flatpak install -y --noninteractive flathub "$@"
  log_change "installed flatpak apps: $*"
  echo ":: Flatpak install complete."
}

emit_pkg() {
  printf 'PKG|%s|%s|%d\n' "$1" "$2" "$(is_installed "$2" && echo 1 || echo 0)"
}

