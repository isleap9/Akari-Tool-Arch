#!/usr/bin/env bash
#
# Akari Tool — one-liner bootstrap for the Arch live ISO.
#
#   curl -fsSL https://raw.githubusercontent.com/isleap9/Akari-Tool-Arch/main/bootstrap.sh | bash
#
# Fetches the tool into the live environment's RAM and starts the installer
# wizard. Nothing is written to any disk until you confirm inside the wizard.
#
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run this as root (you are root on the Arch ISO)."; exit 1; }

if [[ ! -d /run/archiso ]] && ! grep -qi archiso /proc/cmdline 2>/dev/null; then
  echo "This bootstrap is for the Arch live ISO."
  echo "On an installed system, use the akari-tool-cli package instead:"
  echo "  paru -S akari-tool-cli && akari-tui"
  exit 1
fi

DEST=/tmp/akari-tool
echo ":: Fetching Akari Tool"
pacman -Sy --needed --noconfirm git >/dev/null
rm -rf "$DEST"
git clone --depth 1 https://github.com/isleap9/Akari-Tool-Arch "$DEST" >/dev/null

chmod 755 "$DEST"/tui/akari-install "$DEST"/tui/akari-tui \
          "$DEST"/backend/akari-setup.sh "$DEST"/backend/akari-install.sh

# Under `curl … | bash` our stdin is the pipe, not the terminal, so the
# wizard would refuse to start. Hand it the real tty.
if [[ -r /dev/tty ]]; then
  exec "$DEST/tui/akari-install" < /dev/tty
else
  echo "No controlling terminal. Run it directly instead:"
  echo "  $DEST/tui/akari-install"
  exit 1
fi
