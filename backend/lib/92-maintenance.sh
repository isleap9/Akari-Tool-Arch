#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- manual snapshot ---------------------------------------------------
plan_snapshot() {
  echo "== Plan: create snapshot =="
  case "$(snapshot_tool)" in
    snapper)   echo "Will create a snapper snapshot of the root config." ;;
    timeshift) echo "Will create a timeshift snapshot (can take a while)." ;;
    none)      echo "No snapshot tool found."
               echo "Install one first: snapper (btrfs) or timeshift (btrfs/rsync)." ;;
  esac
}

apply_snapshot() {
  if [[ "$(snapshot_tool)" == none ]]; then
    echo ":: No snapshot tool installed (snapper or timeshift)." >&2
    echo "   For btrfs roots: pacman -S snapper snap-pac, then: snapper -c root create-config /" >&2
    return 1
  fi
  snapper_note "manual snapshot from Akari"
  echo ":: Snapshot done."
}

# ---- paru bootstrap ---------------------------------------------------
# Fresh Arch has no AUR helper; everything AUR-related in this tool needs
# one. Build paru from the AUR the manual way (git + makepkg as the user).
plan_paru() {
  echo "== Plan: install paru (AUR helper) =="
  if command -v paru &>/dev/null || command -v yay &>/dev/null; then
    echo "An AUR helper is already installed — nothing to do."
  else
    echo "Will do:"
    echo "  1. pacman -S --needed base-devel git   (build prerequisites)"
    echo "  2. git clone https://aur.archlinux.org/paru.git (as $RUN_USER)"
    echo "  3. makepkg -si                          (build + install as $RUN_USER)"
    echo ""
    echo "Built from source rather than paru-bin: the -bin package ships a"
    echo "prebuilt binary that stops working whenever pacman bumps libalpm's"
    echo "ABI. Building takes a few minutes longer and cannot drift."
  fi
}

apply_paru() {
  if command -v paru &>/dev/null || command -v yay &>/dev/null; then
    echo ":: An AUR helper is already installed."; return 0
  fi
  echo ":: Installing build prerequisites (base-devel, git)"
  run_root pacman -S --needed --noconfirm base-devel git

  local bdir="$RUN_HOME/.cache/akari-paru-build"
  echo ":: Building paru from the AUR (as $RUN_USER) — this takes a few minutes"
  run_user rm -rf "$bdir"
  run_user git clone --depth 1 https://aur.archlinux.org/paru.git "$bdir"

  # makepkg refuses root and needs pacman rights for -si; reuse the same
  # temporary scoped sudoers rule as run_aur when we're the GUI's root.
  if [[ $EUID -eq 0 && -n "${AKARI_USER:-}" ]]; then
    local drop=/etc/sudoers.d/99-akari-aur-tmp rc=0
    printf '%s ALL=(root) NOPASSWD: /usr/bin/pacman\n' "$AKARI_USER" > "$drop"
    chmod 0440 "$drop"
    runuser -u "$AKARI_USER" -- bash -c "cd '$bdir' && makepkg -si --noconfirm" || rc=$?
    rm -f "$drop"
    (( rc )) && { echo ":: paru build failed."; return $rc; }
  else
    ( cd "$bdir" && makepkg -si --noconfirm )
  fi
  run_user rm -rf "$bdir"
  if ! run_user paru --version >/dev/null 2>&1; then
    echo ":: paru was installed but will not start — remove it with"
    echo "   'sudo pacman -Rns paru' and report this."
    return 1
  fi
  log_change "installed paru (AUR helper), built from source"
  echo ":: paru installed. AUR packages are now available in Akari."
}

# ---- mirror optimizer -------------------------------------------------
plan_mirrors() {
  echo "== Plan: optimize pacman mirrors =="
  echo "Will do:"
  is_installed reflector || echo "  - pacman -S reflector"
  echo "  - backup /etc/pacman.d/mirrorlist -> mirrorlist.akari.bak"
  echo "  - reflector: 20 freshest HTTPS mirrors, sorted by download rate"
  echo "  - pacman -Syy (refresh databases against the new mirrors)"
}

apply_mirrors() {
  is_installed reflector || {
    echo ":: Installing reflector"
    run_root pacman -S --needed --noconfirm reflector
  }
  echo ":: Backing up mirrorlist (mirrorlist.akari.bak)"
  run_root cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.akari.bak
  echo ":: Ranking mirrors (this takes ~30s)"
  run_root reflector --protocol https --age 12 --latest 30 --fastest 20 \
    --sort rate --save /etc/pacman.d/mirrorlist
  log_change "optimized mirrorlist via reflector (backup at mirrorlist.akari.bak)"
  echo ":: Refreshing package databases"
  run_root pacman -Syy
  echo ":: Mirrors optimized."
}

# ---- maintenance / cleanup --------------------------------------------
plan_cleanup() {
  echo "== Plan: system cleanup =="
  local cache orph
  cache=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
  orph=$(pacman -Qtdq 2>/dev/null | wc -l)
  echo "Will do:"
  echo "  - trim package cache to 2 most recent versions (currently ${cache:-?})"
  is_installed pacman-contrib || echo "    (installs pacman-contrib for paccache)"
  if (( orph )); then
    echo "  - remove $orph orphaned packages:"
    pacman -Qtdq 2>/dev/null | sed 's/^/      /'
  else
    echo "  - orphan removal: none found"
  fi
}

apply_cleanup() {
  is_installed pacman-contrib || {
    echo ":: Installing pacman-contrib (provides paccache)"
    run_root pacman -S --needed --noconfirm pacman-contrib
  }
  local before after
  before=$(du -sm /var/cache/pacman/pkg 2>/dev/null | cut -f1)
  echo ":: Trimming package cache (keeping 2 versions per package)"
  run_root paccache -rk2
  run_root paccache -ruk0   # drop cached versions of uninstalled packages
  after=$(du -sm /var/cache/pacman/pkg 2>/dev/null | cut -f1)
  echo ":: Cache: ${before:-?} MiB -> ${after:-?} MiB"

  local orphans
  orphans=$(pacman -Qtdq 2>/dev/null || true)
  if [[ -n "$orphans" ]]; then
    echo ":: Removing $(wc -l <<<"$orphans") orphaned packages"
    # shellcheck disable=SC2086
    run_root pacman -Rns --noconfirm $orphans
    log_change "cleanup: removed orphans: $(echo $orphans | tr '\n' ' ')"
  else
    echo ":: No orphaned packages."
  fi
  log_change "cleanup: trimmed pacman cache (${before:-?} -> ${after:-?} MiB)"
  echo ":: Cleanup complete."
}
