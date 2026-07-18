#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- UKI-aware boot handling ------------------------------------------
# Systems like EFI-with-unified-kernel-images build the kernel+initramfs
# into one signed .efi (see the stock preset's default_uki=). A new kernel
# installed the classic way is INVISIBLE to such a boot chain until its
# preset is converted to the same style. Learned the hard way.

STOCK_PRESET=/etc/mkinitcpio.d/linux.preset

stock_uki_path() {
  grep -E '^default_uki=' "$STOCK_PRESET" 2>/dev/null | cut -d'"' -f2 || true
}

boot_uses_uki() { [[ -n "$(stock_uki_path)" ]]; }

# Convert a kernel's preset to UKI style, cloning the stock preset's
# pattern (same ESP directory, same options), then rebuild.
setup_uki_preset() {
  local name="$1"
  local preset="/etc/mkinitcpio.d/${name}.preset"
  [[ -f "$preset" ]] || { echo ":: No preset for $name — skipping UKI setup." >&2; return 1; }

  if grep -Eq '^default_uki=' "$preset"; then
    echo ":: $name preset is already UKI-style."
  else
    local dir target
    dir=$(dirname "$(stock_uki_path)")           # e.g. /boot/EFI/Linux
    target="$dir/arch-${name}.efi"
    echo ":: Converting $preset to UKI style (target: $target)"
    run_root cp "$preset" "${preset}.akari.bak"
    run_root sed -i 's|^default_image=|#default_image=|' "$preset"
    if grep -Eq '^#default_uki=' "$preset"; then
      run_root sed -i "s|^#default_uki=.*|default_uki=\"$target\"|" "$preset"
    else
      echo "default_uki=\"$target\"" | run_root tee -a "$preset" >/dev/null
    fi
    # carry the stock preset's default_options (splash etc.) if ours is inactive
    local opts
    opts=$(grep -E '^default_options=' "$STOCK_PRESET" || true)
    if [[ -n "$opts" ]] && ! grep -Eq '^default_options=' "$preset"; then
      if grep -Eq '^#default_options=' "$preset"; then
        run_root sed -i "s|^#default_options=.*|$opts|" "$preset"
      else
        echo "$opts" | run_root tee -a "$preset" >/dev/null
      fi
    fi
    log_change "converted $preset to UKI style ($target); backup: ${preset}.akari.bak"
  fi

  echo ":: Building unified kernel image for $name"
  run_root mkinitcpio -p "$name"
  if command -v sbctl &>/dev/null; then
    echo ":: sbctl present — the post hook signs the UKI for Secure Boot automatically."
  fi
  # the classic initramfs from the package install is now dead weight
  local leftover="/boot/initramfs-${name}.img"
  if [[ -f "$leftover" ]]; then
    echo ":: Removing now-redundant classic initramfs: $leftover"
    run_root rm -f "$leftover"
    log_change "removed redundant initramfs after UKI conversion: $leftover"
  fi
}

