#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- functional diagnosis ----------------------------------------------
# Unlike 'check' (package presence), these tests exercise the actual
# gaming stack: does Vulkan respond, in both bitnesses, on the right GPU.
# Emits: DIA|key|state|title|detail|fix   (fields sanitized of pipes)

run_diag() {
  printf 'DIA|%s|%s|%s|%s|%s\n' "$1" "$2" \
    "$(tr -d '|' <<<"$3")" "$(tr -d '|' <<<"$4")" "$(tr -d '|' <<<"$5")"
}

cmd_diagnose() {
  local vendors; vendors=$(detect_gpu)

  # -- 64-bit Vulkan: does it respond, and with which devices? ----------
  local devs=""
  if ! command -v vulkaninfo &>/dev/null; then
    run_diag vk64 warn "Vulkan (64-bit)" \
      "vulkaninfo not found — cannot test" \
      "Install vulkan-tools (included in Set up gaming)"
  else
    devs=$(vulkaninfo --summary 2>/dev/null \
           | grep -E 'deviceName' | sed 's/.*= *//' | sort -u \
           | paste -sd ', ' -) || true
    if [[ -n "$devs" ]]; then
      run_diag vk64 ok "Vulkan (64-bit)" "Responding. Devices: $devs" ""
    else
      run_diag vk64 fail "Vulkan (64-bit)" \
        "No Vulkan devices respond — games will not run" \
        "Check the GPU Drivers card on Overview"
    fi
  fi

  # -- Discrete GPU actually visible to Vulkan? --------------------------
  # Desktop trap: monitor plugged into the motherboard, or broken driver,
  # and everything silently renders on the iGPU.
  if [[ "$vendors" == *nvidia* && -n "$devs" ]]; then
    if grep -qiE 'nvidia|geforce|rtx|gtx' <<<"$devs"; then
      run_diag dgpu ok "Discrete GPU (NVIDIA)" \
        "Your NVIDIA card is visible to Vulkan" ""
    else
      run_diag dgpu fail "Discrete GPU (NVIDIA)" \
        "An NVIDIA GPU is in this system but Vulkan cannot see it" \
        "Driver problem or module not loaded — check GPU Drivers, then reboot"
    fi
  fi

  # -- 32-bit Vulkan (what older Windows games via Proton need) ----------
  if [[ ! -e /usr/lib32/libvulkan.so.1 ]]; then
    run_diag vk32 fail "Vulkan (32-bit)" \
      "lib32 Vulkan loader missing — 32-bit games can't render" \
      "Run Set up gaming (installs lib32 packages)"
  else
    local miss32=""
    [[ "$vendors" == *nvidia* && ! -e /usr/lib32/libGLX_nvidia.so.0 ]] && miss32+="lib32-nvidia-utils "
    [[ "$vendors" == *amd*    && ! -e /usr/lib32/libvulkan_radeon.so ]] && miss32+="lib32-vulkan-radeon "
    [[ "$vendors" == *intel*  && ! -e /usr/lib32/libvulkan_intel.so  ]] && miss32+="lib32-vulkan-intel "
    if [[ -z "$miss32" ]]; then
      run_diag vk32 ok "Vulkan (32-bit)" \
        "32-bit loader and GPU drivers present" ""
    else
      run_diag vk32 fail "Vulkan (32-bit)" \
        "32-bit driver missing: $miss32— 32-bit games fall back or fail" \
        "Install from the Gaming page (GPU drivers group)"
    fi
  fi

  # -- gamemode daemon ----------------------------------------------------
  if ! command -v gamemoded &>/dev/null; then
    run_diag gamemode warn "GameMode" \
      "gamemode not installed" \
      "Included in Set up gaming"
  else
    local gm
    gm=$(gamemoded -s 2>&1) || true
    if grep -qi 'is active' <<<"$gm"; then
      run_diag gamemode ok "GameMode" "Daemon reachable — currently active" ""
    elif grep -qi 'is inactive' <<<"$gm"; then
      run_diag gamemode ok "GameMode" \
        "Daemon reachable (inactive — activates when a game requests it)" ""
    else
      run_diag gamemode warn "GameMode" \
        "gamemoded did not respond: $gm" \
        "Log out/in if you were just added to the gamemode group"
    fi
    if ! id -nG "$RUN_USER" 2>/dev/null | grep -qw gamemode; then
      run_diag gamemode_grp warn "GameMode group" \
        "$USER is not in the gamemode group" \
        "Apply tweaks on Overview, then log out and back in"
    fi
  fi

  # -- gamescope & umu ----------------------------------------------------
  if command -v gamescope &>/dev/null; then
    local gsv
    gsv=$(gamescope --version 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
          | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z.\-]*' | head -1)
    run_diag gamescope ok "Gamescope" "Installed${gsv:+ (v$gsv)}" ""
  else
    run_diag gamescope warn "Gamescope" "Not installed" "Included in Set up gaming"
  fi
  if command -v umu-run &>/dev/null; then
    run_diag umu ok "umu launcher" "Installed — Lutris/Heroic can use Proton" ""
  else
    run_diag umu warn "umu launcher" "Not installed" "Included in Set up gaming"
  fi

  # -- Steam libraries on NTFS (classic Proton breaker) -------------------
  local ntfs_mounts m bad=""
  ntfs_mounts=$(findmnt -rn -t ntfs,ntfs3 -o TARGET 2>/dev/null | paste -sd ' ' -) || true
  if [[ -z "$ntfs_mounts" ]]; then
    run_diag ntfs ok "NTFS drives" "No NTFS partitions mounted" ""
  else
    for m in $ntfs_mounts; do
      if find "$m" -maxdepth 3 -type d -name steamapps -print -quit 2>/dev/null | grep -q .; then
        bad+="$m "
      fi
    done
    if [[ -n "$bad" ]]; then
      run_diag ntfs fail "Steam library on NTFS" \
        "steamapps found on NTFS mount(s): $bad— Proton games break on NTFS" \
        "Move the library to an ext4/btrfs drive (recommended)"
    else
      run_diag ntfs warn "NTFS drives" \
        "NTFS mounted at: $ntfs_mounts — fine for storage, do not put Steam libraries there" ""
    fi
  fi

  # -- dkms modules built for every installed kernel? ---------------------
  # The pre-reboot catch: kernel updated but the NVIDIA module not built
  # for it yet = next boot has no driver.
  if is_installed nvidia-open-dkms || is_installed nvidia-dkms; then
    local kver missing_k=""
    for kver in /usr/lib/modules/*/; do
      kver=$(basename "$kver")
      [[ -f "/usr/lib/modules/$kver/pkgbase" ]] || continue   # real kernels only
      if ! dkms status 2>/dev/null | grep -F "$kver" | grep -qi 'nvidia.*installed'; then
        missing_k+="$kver "
      fi
    done
    if [[ -z "$missing_k" ]]; then
      run_diag dkms ok "NVIDIA dkms modules" \
        "Built for every installed kernel" ""
    else
      run_diag dkms fail "NVIDIA dkms modules" \
        "NOT built for: $missing_k— booting these kernels means no NVIDIA driver" \
        "Reinstall the matching linux-*-headers, then: dkms autoinstall"
    fi
  fi

  # -- audio server alive? -------------------------------------------------
  if command -v pactl &>/dev/null; then
    local audio
    audio=$(pactl info 2>/dev/null | grep -E '^Server Name' | sed 's/.*: //') || true
    if [[ -n "$audio" ]]; then
      run_diag audio ok "Audio server" "$audio responding" ""
    else
      run_diag audio fail "Audio server" \
        "No audio server responds — games will be silent" \
        "systemctl --user restart pipewire pipewire-pulse wireplumber"
    fi
  fi

  # -- Flatpak Steam (sandbox caveats) -------------------------------------
  if command -v flatpak &>/dev/null && \
     flatpak list --app 2>/dev/null | grep -qi 'com.valvesoftware.Steam'; then
    run_diag flatpak warn "Flatpak Steam detected" \
      "The sandbox blocks system MangoHud/gamemode and uses different paths" \
      "Prefer the native steam package (installed by Set up gaming)"
  fi

  # -- Game controllers ----------------------------------------------------
  local pads
  pads=$(grep -iE '^N: Name=.*(controller|gamepad|dualsense|dualshock|x-box|xbox|joy-con|pro controller|8bitdo|wireless controller)' \
         /proc/bus/input/devices 2>/dev/null \
         | sed -E 's/^N: Name="(.*)"/\1/' | sort -u | paste -sd ', ' -) || true
  if [[ -n "$pads" ]]; then
    run_diag pads ok "Controllers detected" "$pads" ""
    # permissions layer for non-Xbox pads + Steam Input
    if is_installed game-devices-udev; then
      run_diag pads_udev ok "Controller udev rules" "game-devices-udev installed" ""
    else
      run_diag pads_udev warn "Controller udev rules" \
        "game-devices-udev not installed — PlayStation/Switch/8BitDo pads may lack permissions" \
        "Install game-devices-udev (AUR), then replug the controller"
    fi
    if [[ -e /dev/uinput ]]; then
      run_diag pads_uinput ok "uinput device" "Present (Steam Input can remap)" ""
    else
      run_diag pads_uinput warn "uinput device" \
        "/dev/uinput missing — Steam Input remapping unavailable" \
        "modprobe uinput, or install game-devices-udev"
    fi
  else
    run_diag pads ok "Controllers" "None connected right now (plug one in and re-run to test)" ""
  fi

  # -- Hyprland gaming settings (only when running under Hyprland) --------
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl &>/dev/null; then
    local tearing vrr
    tearing=$(hyprctl getoption general:allow_tearing 2>/dev/null | grep -oE 'int: [01]' | grep -oE '[01]$') || true
    vrr=$(hyprctl getoption misc:vrr 2>/dev/null | grep -oE 'int: [0-9]' | grep -oE '[0-9]$') || true
    if [[ "$tearing" == "1" ]]; then
      run_diag hypr_tear ok "Hyprland: tearing" \
        "allow_tearing enabled — fullscreen games can bypass vsync latency" ""
    else
      run_diag hypr_tear info "Hyprland: tearing" \
        "allow_tearing is off (deliberate for many setups; enables lower-latency fullscreen gaming)" \
        "Optional: general:allow_tearing = true plus an immediate windowrule for games"
    fi
    case "$vrr" in
      1|2) run_diag hypr_vrr ok "Hyprland: VRR" "vrr = $vrr (adaptive sync active)" "" ;;
      0)   run_diag hypr_vrr info "Hyprland: VRR" \
             "vrr = 0 — adaptive sync disabled (fine if your monitor lacks it)" \
             "Optional: misc:vrr = 1 (always) or 2 (fullscreen only)" ;;
      *)   : ;;  # hyprctl unavailable mid-session; skip silently
    esac
  fi

  # -- 32-bit audio (Proton games are 32-bit clients surprisingly often) --
  local a32miss=""
  is_installed lib32-pipewire      || a32miss+="lib32-pipewire "
  is_installed lib32-pipewire-jack || a32miss+="lib32-pipewire-jack "
  if [[ -z "$a32miss" ]]; then
    run_diag audio32 ok "Audio (32-bit)" "lib32 pipewire libraries present" ""
  else
    run_diag audio32 warn "Audio (32-bit)" \
      "Missing: $a32miss— classic cause of silent Proton games" \
      "Run Set up gaming (now includes the audio group)"
  fi

  # -- Controller support -------------------------------------------------
  if ! is_installed game-devices-udev; then
    run_diag ctl_udev warn "Controller udev rules" \
      "game-devices-udev not installed — many gamepads/wheels won't be recognized" \
      "Run Set up gaming (now includes controller support)"
  else
    run_diag ctl_udev ok "Controller udev rules" "game-devices-udev installed" ""
  fi
  if id -nG "$RUN_USER" 2>/dev/null | grep -qw input; then
    run_diag ctl_grp ok "Controller access" "$RUN_USER is in the input group" ""
  else
    run_diag ctl_grp warn "Controller access" \
      "$RUN_USER is not in the input group — some controllers need it" \
      "Apply performance tweaks (adds the group; takes effect next login)"
  fi
  local pads
  pads=$(grep -l . /sys/class/input/js*/device/name 2>/dev/null \
         | xargs -r cat 2>/dev/null | paste -sd ', ' -) || true
  if [[ -n "$pads" ]]; then
    run_diag ctl_dev ok "Connected controllers" "$pads" ""
  else
    run_diag ctl_dev info "Connected controllers" \
      "None detected right now (plug one in and re-run Diagnose)" ""
  fi
}

