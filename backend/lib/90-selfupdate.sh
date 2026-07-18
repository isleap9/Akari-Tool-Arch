#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- self-update -------------------------------------------------------
AKARI_REPO="isleap9/Akari-Tool-Arch"

# Where does this installation live, and how was it installed?
akari_root() {   # repo root when running from a git checkout, else ""
  local here; here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  ( cd "$here" && git rev-parse --show-toplevel 2>/dev/null ) || true
}

akari_install_mode() {   # git | pacman | unknown
  if [[ -n "$(akari_root)" ]]; then echo git
  elif pacman -Qo "${BASH_SOURCE[0]}" &>/dev/null; then echo pacman
  else echo unknown; fi
}

# Latest release tag on GitHub ("v0.2.0" -> "0.2.0"); empty on failure.
# Cached for 6h so routine 'check' runs don't hit the network every time.
akari_latest_version() {
  local cache="${XDG_CACHE_HOME:-$RUN_HOME/.cache}/akari-latest-version"
  if [[ -f "$cache" ]] && \
     (( $(date +%s) - $(stat -c %Y "$cache") < 21600 )); then
    cat "$cache"; return 0
  fi
  local latest
  latest=$(curl -fsSL --max-time 10 \
    "https://api.github.com/repos/$AKARI_REPO/releases/latest" 2>/dev/null \
    | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
  if [[ -n "$latest" ]]; then
    mkdir -p "$(dirname "$cache")" 2>/dev/null
    printf '%s' "$latest" > "$cache" 2>/dev/null || true
  fi
  printf '%s' "$latest"
}

check_update() {
  local latest; latest=$(akari_latest_version)
  if [[ -z "$latest" ]]; then
    emit update unknown "Akari $AKARI_VERSION — could not check for updates (offline?)"
  elif [[ "$latest" == "$AKARI_VERSION" ]]; then
    emit update ok "Akari $AKARI_VERSION — up to date"
  else
    emit update warn "Akari $AKARI_VERSION — version $latest is available"
  fi
}

plan_self_update() {
  echo "== Plan: update Akari Tool =="
  local latest; latest=$(akari_latest_version)
  [[ -n "$latest" && "$latest" == "$AKARI_VERSION" ]] && {
    echo "Already up to date ($AKARI_VERSION)."; return 0; }
  [[ -n "$latest" ]] && echo "Current: $AKARI_VERSION -> Latest: $latest"
  case "$(akari_install_mode)" in
    git)    echo "Installed from source — will run: git pull --ff-only"
            echo "  in $(akari_root)"
            echo "Then restart Akari to load the new version." ;;
    pacman) echo "Installed as a package — will update akari-tool via your AUR helper." ;;
    *)      echo "Could not determine how Akari was installed."
            echo "Update manually: git pull in your checkout, or reinstall the package." ;;
  esac
}

apply_self_update() {
  local mode; mode=$(akari_install_mode)
  case "$mode" in
    git)
      local root; root=$(akari_root)
      echo ":: Updating Akari via git pull ($root)"
      # the checkout belongs to the user — run git as them, not as root
      if run_user git -C "$root" pull --ff-only; then
        log_change "self-update: git pull in $root"
        echo ":: Updated. Restart Akari to load the new version."
      else
        echo ":: git pull failed — local changes in the way?" >&2
        echo "   Try: git -C $root stash && git -C $root pull" >&2
        return 1
      fi ;;
    pacman)
      local helper=""
      command -v paru &>/dev/null && helper=paru
      [[ -z "$helper" ]] && command -v yay &>/dev/null && helper=yay
      if [[ -z "$helper" ]]; then
        echo ":: akari-tool is a package but no AUR helper was found." >&2
        echo "   Install paru from the Maintenance page first." >&2
        return 1
      fi
      echo ":: Updating akari-tool via $helper"
      run_aur "$helper" -S --needed --noconfirm akari-tool
      log_change "self-update: akari-tool via $helper"
      echo ":: Updated. Restart Akari to load the new version." ;;
    *)
      echo ":: Cannot self-update: unknown install method." >&2
      return 1 ;;
  esac
}


