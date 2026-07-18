#!/usr/bin/env bash
#
# release.sh — one-command release for Akari Tool
#
# Usage:  ./release.sh 0.3.0
#
# Does, in order:
#   1. bump the version everywhere (backend, GUI footer, PKGBUILD)
#   2. commit, tag v<ver>, push to GitHub
#   3. create the GitHub release (needed for the in-app update check)
#   4. download the release tarball, compute its sha256
#   5. update the AUR package (PKGBUILD + .SRCINFO) and push it
#
# Requirements:
#   - run from the root of the Akari-Tool-Arch checkout
#   - gh (GitHub CLI), logged in:  pacman -S github-cli && gh auth login
#   - your AUR SSH key set up (you already have this)
#
set -euo pipefail

REPO="isleap9/Akari-Tool-Arch"
AUR_REMOTE="ssh://aur@aur.archlinux.org/akari-tool.git"
AUR_DIR="${AUR_DIR:-$HOME/.cache/akari-aur-release}"

VER="${1:-}"
[[ -z "$VER" ]] && { echo "usage: $0 <new-version>  (e.g. $0 0.3.0)"; exit 1; }
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3"; exit 1; }

# sanity: are we in the repo root?
[[ -f backend/akari-setup.sh && -f packaging/PKGBUILD ]] || {
  echo "Run this from the root of the Akari-Tool-Arch checkout."; exit 1; }

command -v gh >/dev/null || { echo "Install github-cli first: sudo pacman -S github-cli && gh auth login"; exit 1; }

OLD=$(grep -oP 'AKARI_VERSION="\K[^"]+' backend/akari-setup.sh)
echo "==> Releasing: $OLD -> $VER"

# refuse to release a dirty tree (version bumps aside)
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree not clean — commit or stash first:"; git status --short; exit 1
fi

# ---- 1. bump version everywhere ----------------------------------------
echo "==> Bumping version strings"
sed -i "s/AKARI_VERSION=\"$OLD\"/AKARI_VERSION=\"$VER\"/" backend/akari-setup.sh
sed -i "s/pkgver=$OLD/pkgver=$VER/" packaging/PKGBUILD
sed -i "s/pkgrel=[0-9]*/pkgrel=1/" packaging/PKGBUILD
# GUI footer shows major.minor only
sed -i "s/v${OLD%.*} · bash backend/v${VER%.*} · bash backend/" ui/Main.qml || true

# ---- 2. commit, tag, push ----------------------------------------------
echo "==> Committing and tagging v$VER"
git add backend/akari-setup.sh packaging/PKGBUILD ui/Main.qml
git commit -m "Release $VER"
git tag "v$VER"
git push origin HEAD "v$VER"

# ---- 3. GitHub release (the in-app updater reads releases/latest) ------
echo "==> Creating GitHub release v$VER"
gh release create "v$VER" --repo "$REPO" \
  --title "Akari Tool $VER" --generate-notes

# ---- 4. tarball checksum ------------------------------------------------
echo "==> Fetching release tarball for checksum"
TARBALL_URL="https://github.com/$REPO/archive/refs/tags/v$VER.tar.gz"
TMP=$(mktemp)
# the tag can take a few seconds to be downloadable
for i in {1..10}; do
  curl -fsSL -o "$TMP" "$TARBALL_URL" && break
  echo "   (not ready yet — retry $i/10)"; sleep 3
done
SHA=$(sha256sum "$TMP" | cut -d' ' -f1)
echo "   sha256: $SHA"
sed -i "s/^sha256sums=.*/sha256sums=('$SHA')/" packaging/PKGBUILD
rm -f "$TMP"

# commit the checksum back to the repo so packaging/ stays truthful
git add packaging/PKGBUILD
git commit -m "packaging: checksum for $VER"
git push

# ---- 5. update the AUR package -----------------------------------------
echo "==> Updating AUR package"
if [[ -d "$AUR_DIR/.git" ]]; then
  git -C "$AUR_DIR" pull --ff-only
else
  git clone "$AUR_REMOTE" "$AUR_DIR"
fi
cp packaging/PKGBUILD "$AUR_DIR/PKGBUILD"
[[ -f "$AUR_DIR/.gitignore" ]] || printf '%s\n' '*.tar.gz' '*.tar.zst' 'pkg/' 'src/' > "$AUR_DIR/.gitignore"

( cd "$AUR_DIR"
  makepkg --printsrcinfo > .SRCINFO
  git add PKGBUILD .SRCINFO .gitignore
  git commit -m "Update to $VER"
  git push )

echo ""
echo "==> Done! Released $VER:"
echo "    GitHub : https://github.com/$REPO/releases/tag/v$VER"
echo "    AUR    : https://aur.archlinux.org/packages/akari-tool"
echo ""
echo "    Users get it via 'paru -Syu' or Akari's own Update card."
