#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

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

  local vendors v pkgs=( "${PKGS_CORE[@]}" "${PKGS_DEPS[@]}" "${PKGS_FONTS[@]}"
                         "${PKGS_AUDIO[@]}" "${PKGS_CONTROLLER[@]}" )
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
    snapper_note "gaming setup"
    echo ":: Installing $(wc -l <<<"$missing") packages via pacman"
    # shellcheck disable=SC2086
    run_root pacman -S --needed --noconfirm $missing
    log_change "installed gaming packages: $(echo $missing | tr '\n' ' ')"
  fi

  # Optional AUR extras — now installed in BOTH CLI and GUI modes
  local helper=""
  command -v paru &>/dev/null && helper=paru
  [[ -z "$helper" ]] && command -v yay &>/dev/null && helper=yay
  if [[ -n "$helper" ]]; then
    missing=$(missing_from "${PKGS_AUR_OPTIONAL[@]}")
    if [[ -n "$missing" ]]; then
      echo ":: Installing optional AUR packages via $helper"
      # shellcheck disable=SC2086
      if run_aur "$helper" -S --needed --noconfirm $missing; then
        log_change "installed AUR extras: $(echo $missing | tr '\n' ' ')"
      else
        echo ":: (AUR extras failed — continuing, they are optional)"
      fi
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
  if ! id -nG "$RUN_USER" | grep -qw input; then
    echo ":: Adding $RUN_USER to input group for controller access (takes effect next login)"
    run_root usermod -aG input "$RUN_USER"
    log_change "added $RUN_USER to input group"
  fi
  echo ":: Tweaks applied. Changes are logged in $LOGFILE"
}

# Latest Arch news headlines (title + date), newest first. Cached 6h so
# routine plan/check runs don't hit the network. Empty output on failure.
arch_news() {   # arch_news [count]
  local count="${1:-3}"
  local cache="${XDG_CACHE_HOME:-$RUN_HOME/.cache}/akari-arch-news"
  mkdir -p "$(dirname "$cache")" 2>/dev/null || true
  if [[ ! -f "$cache" ]] || \
     (( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) >= 21600 )); then
    curl -fsSL --max-time 10 https://archlinux.org/feeds/news/ 2>/dev/null \
      | tr -d '\n' \
      | grep -oE '<item>.*</item>' \
      | sed -E 's|</item>|</item>\n|g' \
      | sed -nE 's|.*<title>([^<]+)</title>.*<pubDate>([A-Za-z]+, [0-9]+ [A-Za-z]+ [0-9]+)[^<]*</pubDate>.*|\2 — \1|p' \
      > "$cache".tmp 2>/dev/null && mv "$cache".tmp "$cache" || rm -f "$cache".tmp
  fi
  [[ -f "$cache" ]] && head -n "$count" "$cache"
  return 0
}

plan_sysupdate() {
  echo "== Plan: full system upgrade =="
  echo "Will run: pacman -Syu (all packages updated to current)"
  echo ""
  # Pending updates (checkupdates syncs to a temp db — safe, no partial-update risk)
  if command -v checkupdates &>/dev/null; then
    local pending
    pending=$(checkupdates 2>/dev/null || true)
    if [[ -n "$pending" ]]; then
      echo "Pending updates ($(wc -l <<<"$pending")):"
      sed 's/^/  /' <<<"$pending"
      if grep -qE '^linux(-zen|-lts|-cachyos[a-z-]*)? ' <<<"$pending"; then
        echo "  ! A kernel is in this update — a reboot will be needed afterwards."
      fi
    else
      echo "Pending updates: none — system is current."
    fi
  else
    echo "(install pacman-contrib to preview pending updates here)"
  fi
  # Arch news — the one thing you're supposed to read before -Syu
  local news; news=$(arch_news 3 || true)
  if [[ -n "$news" ]]; then
    echo ""
    echo "Latest Arch news (check for manual-intervention notices):"
    sed 's/^/  /' <<<"$news"
    echo "  Full posts: https://archlinux.org/news/"
  fi
  echo ""
  case "$(snapshot_tool)" in
    snapper)   echo "A snapper snapshot will be taken first." ;;
    timeshift) echo "A timeshift snapshot will be taken first." ;;
    none)      echo "No snapshot tool installed — this upgrade cannot be rolled back at the filesystem level." ;;
  esac
  echo "Afterwards Akari scans for new .pacnew config files and checks whether a reboot is needed."
  return 0
}

apply_sysupdate() {
  snapper_note "full system upgrade"
  local start; start=$(date +%s)
  echo ":: Running full system upgrade (pacman -Syu)"
  run_root pacman -Syu --noconfirm
  log_change "ran full system upgrade (pacman -Syu)"

  # New .pacnew / .pacsave files from this upgrade — silent config drift
  # is how systems rot; at least tell the user they exist.
  local pacnew
  pacnew=$(find /etc \( -name '*.pacnew' -o -name '*.pacsave' \) \
             -newermt "@$start" 2>/dev/null || true)
  if [[ -n "$pacnew" ]]; then
    echo ""
    echo ":: This upgrade left new config files to review:"
    sed 's/^/     /' <<<"$pacnew"
    echo ":: Compare each with its original (e.g. 'pacman -S pacman-contrib; pacdiff')"
    log_change "sysupdate left pacnew/pacsave files: $(echo $pacnew | tr '\n' ' ')"
  fi

  # Classic "am I running a ghost kernel" check: if the running kernel's
  # module directory is gone, the kernel package was upgraded underneath us.
  if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
    echo ""
    echo ":: The running kernel was upgraded — its modules are gone from disk."
    echo ":: REBOOT SOON: new USB devices, filesystems etc. can fail until you do."
  fi
  echo ""
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

  # Preset debris: pacman leaves a .pacsave of the (converted) preset, and
  # setup_uki_preset left a .akari.bak of the original. With the kernel
  # gone, both are orphans.
  local p
  for p in "/etc/mkinitcpio.d/${name}.preset.pacsave" \
           "/etc/mkinitcpio.d/${name}.preset.akari.bak"; do
    if run_root test -f "$p"; then
      echo ":: Deleting orphaned preset file: $p"
      run_root rm -f "$p"
      log_change "deleted orphaned preset: $p"
    fi
  done

  update_bootloader
  echo ":: $name removed. If a custom GRUB entry (40_custom) referenced it,"
  echo "   edit /etc/grub.d/40_custom and regenerate grub.cfg."
}

