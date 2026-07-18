#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- system-wide app list (Apps page) ----------------------------------
# Shows what the USER installed (pacman -Qe = explicit), not the hundreds
# of libraries that came along as dependencies. Critical system packages
# are marked protected so the GUI never offers to remove them.
PROTECTED_PKGS=" base base-devel linux linux-lts linux-zen linux-hardened
  linux-cachyos linux-firmware mkinitcpio systemd sudo pacman bash
  coreutils util-linux filesystem glibc grub efibootmgr networkmanager
  network-manager-applet dhcpcd iwd sof-firmware amd-ucode intel-ucode "

is_protected() {
  [[ $PROTECTED_PKGS == *" $1 "* ]] && return 0
  # kernels + their headers, and anything providing the running session
  [[ $1 == linux-*-headers || $1 == *-ucode ]] && return 0
  return 1
}

cmd_apps() {
  # APP|source|name|version|size|protected|description
  local line name ver size desc
  while IFS= read -r line; do
    name=${line%% *}; ver=${line#* }
    size=$(pacman -Qi "$name" 2>/dev/null \
           | grep -m1 '^Installed Size' | sed 's/.*: //')
    desc=$(pacman -Qi "$name" 2>/dev/null \
           | grep -m1 '^Description' | sed 's/.*: //' | tr -d '|')
    printf 'APP|pacman|%s|%s|%s|%d|%s\n' \
      "$name" "$ver" "${size:-?}" "$(is_protected "$name" && echo 1 || echo 0)" "$desc"
  done < <(pacman -Qe 2>/dev/null)

  if command -v flatpak &>/dev/null; then
    while IFS=$'\t' read -r fname appid fver fsize; do
      [[ -z "$appid" ]] && continue
      printf 'APP|flatpak|%s|%s|%s|0|%s\n' \
        "$appid" "$fver" "$fsize" "$(tr -d '|' <<<"$fname")"
    done < <(flatpak list --app --columns=name,application,version,size 2>/dev/null)
  fi
}

# ---- package uninstaller ----------------------------------------------
# Splits like apply_selected: Flatpak app-ids vs pacman packages.
# pacman -Rns removes the package, its now-unneeded deps, and its config;
# it naturally refuses if something else still depends on the package.
split_remove() {   # sets REM_FLAT / REM_PAC arrays from "$@"
  REM_FLAT=(); REM_PAC=()
  local known_flat=" " entry p
  for entry in "${FLATPAK_APPS[@]}"; do known_flat+="${entry%%|*} "; done
  for p in "$@"; do
    if [[ $known_flat == *" $p "* ]] || [[ $p == *.*.* ]]; then
      REM_FLAT+=("$p")
    else
      REM_PAC+=("$p")
    fi
  done
}

plan_remove() {
  [[ $# -eq 0 ]] && { echo "Nothing selected."; return 0; }
  echo "== Plan: uninstall =="
  split_remove "$@"
  if ((${#REM_PAC[@]})); then
    echo "pacman will remove (incl. unneeded dependencies & config):"
    # -Rnsp prints the full removal list without doing anything
    if ! pacman -Rnsp --print-format '  %n-%v' "${REM_PAC[@]}" 2>&1; then
      echo "  (a package above is required by others — pacman will refuse;"
      echo "   remove the dependent packages first)"
    fi
  fi
  ((${#REM_FLAT[@]})) && { echo "Flatpak will remove:"; printf '  %s\n' "${REM_FLAT[@]}"; }
  return 0
}

apply_remove() {
  [[ $# -eq 0 ]] && { echo "Nothing selected."; return 0; }
  local p
  for p in "$@"; do
    if is_protected "$p"; then
      echo ":: Refusing to remove '$p' — it is critical for a working system." >&2
      return 1
    fi
  done
  split_remove "$@"
  if ((${#REM_PAC[@]})); then
    snapper_note "uninstall: ${REM_PAC[*]}"
    echo ":: Removing ${#REM_PAC[@]} package(s) via pacman -Rns"
    if run_root pacman -Rns --noconfirm "${REM_PAC[@]}"; then
      log_change "removed packages: ${REM_PAC[*]}"
    else
      echo ":: pacman refused (something still depends on a selected package)."
      echo "   Check the plan preview — dependents must be removed first."
      return 1
    fi
  fi
  if ((${#REM_FLAT[@]})); then
    echo ":: Removing ${#REM_FLAT[@]} Flatpak app(s)"
    run_root flatpak uninstall -y --noninteractive "${REM_FLAT[@]}"
    log_change "removed flatpak apps: ${REM_FLAT[*]}"
  fi
  echo ":: Uninstall complete."
}

