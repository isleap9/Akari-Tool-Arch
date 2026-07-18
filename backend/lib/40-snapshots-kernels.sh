#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- snapshots --------------------------------------------------------
# Take a real pre-change snapshot when a supported tool is available:
#   snapper   — skipped if snap-pac is installed (it already snapshots
#               every pacman transaction; doubling up is just noise)
#   timeshift — used when snapper is absent
# Never fatal: a failed snapshot prints a warning and the apply continues.
snapshot_tool() {
  if command -v snapper &>/dev/null && snapper list-configs 2>/dev/null | grep -qw root; then
    echo snapper
  elif command -v timeshift &>/dev/null; then
    echo timeshift
  else
    echo none
  fi
}

snapper_note() {   # snapper_note [description]
  local desc="${1:-akari change}"
  case "$(snapshot_tool)" in
    snapper)
      if is_installed snap-pac; then
        echo ":: snap-pac detected — pacman transactions are snapshotted automatically."
      else
        local num
        num=$(run_root snapper -c root create -t single -c number \
                --description "akari: $desc" --print-number 2>/dev/null) || true
        if [[ -n "$num" ]]; then
          echo ":: snapper snapshot #$num created (akari: $desc)"
          log_change "created snapper snapshot #$num before: $desc"
        else
          echo ":: (snapper snapshot failed — continuing without one)"
        fi
      fi ;;
    timeshift)
      echo ":: Creating timeshift snapshot (akari: $desc) — this can take a moment"
      if run_root timeshift --create --comments "akari: $desc" --scripted >/dev/null 2>&1; then
        echo ":: timeshift snapshot created"
        log_change "created timeshift snapshot before: $desc"
      else
        echo ":: (timeshift snapshot failed — continuing without one)"
      fi ;;
    none) : ;;   # nothing installed — silent, as before
  esac
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

# Add the official CachyOS package repository (prebuilt kernels — no
# compiling). Fully non-interactive: imports their key, installs keyring +
# mirrorlist from the mirror, and appends the repo matching this CPU's
# x86-64 feature level (v4 > v3 > baseline). Safe to call repeatedly.
CACHYOS_MIRROR="https://mirror.cachyos.org/repo/x86_64/cachyos"

setup_cachyos_repo() {
  if grep -Eq '^\s*\[cachyos' /etc/pacman.conf; then
    echo ":: CachyOS repo already configured."
    return 0
  fi

  echo ":: Adding the official CachyOS repository (one-time setup)"
  snapper_note "add cachyos repo"

  # 1) Their signing key
  run_root pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
  run_root pacman-key --lsign-key F3B607488DB35A47

  # 2) Keyring + mirrorlists straight from their mirror (versionless symlinks)
  run_root pacman -U --noconfirm \
    "${CACHYOS_MIRROR}/cachyos-keyring.pkg.tar.zst" \
    "${CACHYOS_MIRROR}/cachyos-mirrorlist.pkg.tar.zst" \
    "${CACHYOS_MIRROR}/cachyos-v3-mirrorlist.pkg.tar.zst" \
    "${CACHYOS_MIRROR}/cachyos-v4-mirrorlist.pkg.tar.zst"

  # 3) Pick the optimized repo tier this CPU supports
  local level
  level=$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null \
            | grep -Eo 'x86-64-v[34] \(supported' \
            | grep -Eo 'v[34]' | sort -r | head -n1 || true)
  echo ":: CPU feature level: x86-64-${level:-baseline}"

  {
    echo ""
    echo "# Added by Akari Tool — official CachyOS repos"
    case "$level" in
      v4)
        echo "[cachyos-v4]"
        echo "Include = /etc/pacman.d/cachyos-v4-mirrorlist"
        echo "[cachyos-core-v4]"
        echo "Include = /etc/pacman.d/cachyos-v4-mirrorlist"
        echo "[cachyos-extra-v4]"
        echo "Include = /etc/pacman.d/cachyos-v4-mirrorlist"
        ;;
      v3)
        echo "[cachyos-v3]"
        echo "Include = /etc/pacman.d/cachyos-v3-mirrorlist"
        echo "[cachyos-core-v3]"
        echo "Include = /etc/pacman.d/cachyos-v3-mirrorlist"
        echo "[cachyos-extra-v3]"
        echo "Include = /etc/pacman.d/cachyos-v3-mirrorlist"
        ;;
    esac
    echo "[cachyos]"
    echo "Include = /etc/pacman.d/cachyos-mirrorlist"
  } | run_root tee -a /etc/pacman.conf >/dev/null

  run_root pacman -Sy
  log_change "added official CachyOS repositories to pacman.conf"
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
  elif [[ $source == cachyos ]]; then
    setup_cachyos_repo
    snapper_note "install kernel $name"
    echo ":: Installing $name + ${name}-headers via pacman (prebuilt — no compiling)"
    run_root pacman -S --needed --noconfirm "$name" "${name}-headers"
    log_change "installed kernel: $name (cachyos repo)"
  elif [[ $source == repo ]]; then
    snapper_note "install kernel $name"
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
    snapper_note "install kernel $name (AUR)"
    echo ":: Installing $name + ${name}-headers via $helper (this compiles — can take a long time)"
    run_aur "$helper" -S --needed --noconfirm "$name" "${name}-headers"
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

  local repo=() aurp=() flat=() p entry
  local known_aur=" ${PKGS_AUR_OPTIONAL[*]} ${PKGS_APPS_AUR[*]} "
  local known_flat=" "
  for entry in "${FLATPAK_APPS[@]}"; do known_flat+="${entry%%|*} "; done
  for p in "$@"; do
    if   [[ $known_flat == *" $p "* ]]; then flat+=("$p")
    elif [[ $known_aur  == *" $p "* ]]; then aurp+=("$p")
    else repo+=("$p"); fi
  done

  if ((${#repo[@]})); then
    snapper_note "install selected packages"
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
      if run_aur "$helper" -S --needed --noconfirm "${aurp[@]}"; then
        log_change "installed selected AUR packages: ${aurp[*]}"
      else
        echo ":: (AUR install failed — continuing)"
      fi
    else
      echo ":: No AUR helper — skipped: ${aurp[*]}"
    fi
  fi
  if ((${#flat[@]})); then
    apply_flatpak "${flat[@]}"
  fi
  echo ":: Selected install complete."
}

