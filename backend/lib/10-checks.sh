#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

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
  # VGA/3D/Display controllers, matched by PCI *vendor ID* — never by name.
  # (Name matching is a trap: "VGA compatible" contains "ati", so every GPU
  # on every system used to be detected as AMD as well.)
  #   10de = NVIDIA, 1002 = AMD/ATI, 8086 = Intel
  local pci vendors=""
  pci=$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d controller|display controller' || true)
  grep -q '\[10de:' <<<"$pci" && vendors+="nvidia "
  grep -q '\[1002:' <<<"$pci" && vendors+="amd "
  grep -q '\[8086:' <<<"$pci" && vendors+="intel "
  echo "${vendors:-unknown}"
}

# Best-effort human GPU model for a vendor, from its lspci line.
# "…NVIDIA Corporation GB205 [GeForce RTX 5070]…" -> "GeForce RTX 5070"
gpu_model() {
  local vendor=$1 line model="" id=""
  case $vendor in
    nvidia) id="10de" ;;
    amd)    id="1002" ;;
    intel)  id="8086" ;;
  esac
  line=$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d controller|display controller' \
         | grep "\[$id:" | head -1)
  # prefer a bracketed marketing name (GeForce/RTX/Radeon/Arc/Iris/UHD…)
  model=$(grep -oE '\[(GeForce|RTX|GTX|Radeon|Arc|Iris|UHD)[^]]*\]' <<<"$line" \
          | head -1 | tr -d '[]')
  # fallback: device description after "controller:", minus vendor boilerplate
  [[ -z "$model" ]] && model=$(sed -E \
      's/.*(controller|Display)[^:]*: //I;
       s/ \(rev.*//;
       s/\[[0-9a-f]{4}:[0-9a-f]{4}\]//g;
       s/(NVIDIA Corporation|Advanced Micro Devices, Inc\.|Intel Corporation) *//g;
       s/\[(AMD\/ATI|AMD|ATI)\] *//g;
       s/^ +| +$//g' <<<"$line")
  model=$(sed -E 's/^ +| +$//g' <<<"$model")
  echo "${model:-$vendor}"
}

check_gpu() {
  local vendors; vendors=$(detect_gpu)
  local v missing model
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
    model=$(gpu_model "$v")
    if [[ -z "$missing" ]]; then
      emit "gpu_$v" ok "$model — $v drivers installed"
    else
      emit "gpu_$v" warn "$model — $v drivers incomplete: $(echo $missing | tr '\n' ' ')"
    fi
  done
}

check_cpu() {
  local model cores
  model=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- \
          | sed -E 's/^ +//; s/\((R|TM|C)\)//gI; s/ CPU//; s/ +@.*//; s/ +/ /g')
  [[ -z "$model" ]] && model=$(lscpu 2>/dev/null | grep -m1 'Model name' \
          | cut -d: -f2- | sed -E 's/^ +//')
  cores=$(nproc 2>/dev/null || echo "?")
  if [[ -n "$model" ]]; then
    emit cpu ok "$model — ${cores} threads"
  else
    emit cpu warn "Could not detect CPU model"
  fi
}

check_ram() {
  # Total + currently available, from /proc/meminfo (no root needed)
  local total_kb avail_kb total_gib avail_gib
  total_kb=$(grep -m1 '^MemTotal:'     /proc/meminfo 2>/dev/null | awk '{print $2}')
  avail_kb=$(grep -m1 '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}')
  if [[ -z "$total_kb" ]]; then
    emit ram warn "Could not read memory info"
    return
  fi
  total_gib=$(awk "BEGIN { printf \"%.0f\", $total_kb / 1048576 }")
  if [[ -n "$avail_kb" ]]; then
    avail_gib=$(awk "BEGIN { printf \"%.1f\", $avail_kb / 1048576 }")
    emit ram ok "${total_gib} GiB — ${avail_gib} GiB free"
  else
    emit ram ok "${total_gib} GiB"
  fi
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

check_flatpak() {
  if flatpak_ready; then
    local n
    n=$(flatpak list --app 2>/dev/null | wc -l)
    emit flatpak ok "Flatpak + Flathub ready ($n app(s) installed)"
  elif command -v flatpak &>/dev/null; then
    emit flatpak warn "Flatpak installed but Flathub remote missing"
  else
    emit flatpak warn "Flatpak not set up — AUR-free app installs unavailable"
  fi
}

check_snapshots() {
  case "$(snapshot_tool)" in
    snapper)
      if is_installed snap-pac; then
        emit snapshots ok "snapper + snap-pac — every install is snapshotted"
      else
        emit snapshots ok "snapper found — Akari snapshots before each change"
      fi ;;
    timeshift) emit snapshots ok "timeshift found — Akari snapshots before each change" ;;
    none)      emit snapshots warn "No snapshot tool — changes cannot be rolled back at the filesystem level" ;;
  esac
}

check_mirrors() {
  local ml=/etc/pacman.d/mirrorlist age_days
  [[ -f $ml ]] || { emit mirrors warn "No mirrorlist found"; return; }
  age_days=$(( ( $(date +%s) - $(stat -c %Y "$ml") ) / 86400 ))
  if (( age_days <= 30 )); then
    emit mirrors ok "Mirrorlist updated $age_days day(s) ago"
  else
    emit mirrors warn "Mirrorlist is $age_days days old — optimize for faster downloads"
  fi
}

check_cache() {
  local mib orph
  mib=$(du -sm /var/cache/pacman/pkg 2>/dev/null | cut -f1); mib=${mib:-0}
  orph=$(pacman -Qtdq 2>/dev/null | wc -l)
  if (( mib > 5120 || orph > 0 )); then
    emit cache warn "Package cache: ${mib} MiB, orphans: $orph — cleanup recommended"
  else
    emit cache ok "Package cache: ${mib} MiB, no orphans"
  fi
}

cmd_check() {
  check_arch
  check_root
  check_network
  check_multilib
  check_cpu
  check_ram
  check_gpu
  check_gaming
  check_proton
  check_aur_helper
  check_tweaks
  check_staleness
  check_mirrors
  check_cache
  check_snapshots
  check_flatpak
  check_update
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
  for p in "${PKGS_APPS_REPO[@]}";  do emit_pkg apps  "$p"; done
  for p in "${PKGS_AUDIO[@]}";      do emit_pkg audio "$p"; done
  for p in "${PKGS_CONTROLLER[@]}"; do emit_pkg input "$p"; done
  if command -v paru &>/dev/null || command -v yay &>/dev/null; then
    for p in "${PKGS_AUR_OPTIONAL[@]}"; do emit_pkg aur "$p"; done
    for p in "${PKGS_APPS_AUR[@]}";    do emit_pkg aur "$p"; done
  fi
  if flatpak_ready; then
    local entry appid
    for entry in "${FLATPAK_APPS[@]}"; do
      appid="${entry%%|*}"
      printf 'PKG|%s|%s|%d\n' flatpak "$appid" \
        "$(flatpak_installed "$appid" && echo 1 || echo 0)"
    done
  fi
}

