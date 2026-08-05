#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- Proton / Wine-GE compatibility tools -----------------------------
# Downloads GloriousEggroll's builds straight from GitHub releases into the
# directory the target launcher scans, verifying the published sha512sum.
#
# Read-mostly by design: the only writes are "unpack a tarball into a
# user-owned directory" and "delete a directory we unpacked earlier".
# Nothing here needs root, and running as root would actively break it —
# Steam silently ignores root-owned entries in compatibilitytools.d.
#
# Tracks (see PROTON_TRACKS): a track is a GitHub repo + an asset name
# pattern + the launchers it makes sense for. Steam wants Proton builds;
# Lutris and Heroic want Wine builds. Keeping them apart stops the tool
# from dropping a Proton build where a Wine build belongs.

# name|repo|asset-glob|targets
PROTON_TRACKS=(
  "proton-ge|GloriousEggroll/proton-ge-custom|GE-Proton*.tar.gz|steam,heroic-proton"
  "wine-ge|GloriousEggroll/wine-ge-custom|wine-lutris-GE-Proton*.tar.xz|lutris,heroic-wine"
)

PROTON_CACHE="${XDG_CACHE_HOME:-$RUN_HOME/.cache}/akari-tool"
PROTON_CACHE_TTL=3600     # seconds; GitHub allows 60 unauthenticated calls/hour

# ---- install locations -------------------------------------------------
# Where each launcher looks for hand-installed compatibility tools.
proton_target_dir() {   # proton_target_dir <target>
  case "$1" in
    steam)
      local b
      for b in "$RUN_HOME/.steam/root/compatibilitytools.d" \
               "$RUN_HOME/.local/share/Steam/compatibilitytools.d" \
               "$RUN_HOME/.steam/steam/compatibilitytools.d"; do
        [[ -d "$b" ]] && { echo "$b"; return; }
      done
      # Not created yet — use the canonical path, which is a symlink target
      # of every Steam layout.
      echo "$RUN_HOME/.steam/root/compatibilitytools.d" ;;
    lutris)        echo "$RUN_HOME/.local/share/lutris/runners/wine" ;;
    heroic-proton) echo "$RUN_HOME/.config/heroic/tools/proton" ;;
    heroic-wine)   echo "$RUN_HOME/.config/heroic/tools/wine" ;;
    *) return 1 ;;
  esac
}

proton_target_label() {
  case "$1" in
    steam)         echo "Steam" ;;
    lutris)        echo "Lutris" ;;
    heroic-proton) echo "Heroic (Proton)" ;;
    heroic-wine)   echo "Heroic (Wine)" ;;
    *)             echo "$1" ;;
  esac
}

# Only offer targets whose launcher is actually present, so the page does
# not invite the user to install a runner for something they do not have.
proton_target_present() {
  case "$1" in
    steam)  is_installed steam || [[ -d "$RUN_HOME/.steam" ]] ;;
    lutris) is_installed lutris || [[ -d "$RUN_HOME/.local/share/lutris" ]] ;;
    heroic-proton|heroic-wine)
      [[ -d "$RUN_HOME/.config/heroic" ]] \
        || is_installed heroic-games-launcher-bin \
        || is_installed heroic-games-launcher ;;
    *) return 1 ;;
  esac
}

proton_track_field() {   # proton_track_field <track> <1..4>
  local entry
  for entry in "${PROTON_TRACKS[@]}"; do
    [[ ${entry%%|*} == "$1" ]] || continue
    printf '%s\n' "$entry" | cut -d'|' -f"$2"
    return 0
  done
  return 1
}

# ---- GitHub release metadata ------------------------------------------
# Cached on disk: the Proton page refreshes on every visit, and burning
# through the 60/hour unauthenticated budget would leave the page blank.
proton_fetch_releases() {   # proton_fetch_releases <repo>  -> cache file path
  local repo="$1"
  local cache="$PROTON_CACHE/gh-${repo//\//_}.json"
  mkdir -p "$PROTON_CACHE" 2>/dev/null || true
  if [[ -s "$cache" ]]; then
    local age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
    (( age < PROTON_CACHE_TTL )) && { echo "$cache"; return 0; }
  fi
  # PROTON_OFFLINE keeps the Overview snappy: `check` runs on every refresh
  # and must never block on a 20-second network timeout, so it settles for
  # whatever the cache already has.
  if [[ -n "${PROTON_OFFLINE:-}" ]]; then
    [[ -s "$cache" ]] && { echo "$cache"; return 0; }
    return 1
  fi
  local tmp="$cache.tmp.$$"
  if curl -fsSL --max-time 20 \
       -H 'Accept: application/vnd.github+json' \
       "https://api.github.com/repos/$repo/releases?per_page=8" -o "$tmp" 2>/dev/null
  then
    mv -f "$tmp" "$cache"
  else
    rm -f "$tmp"
    # Stale cache beats no data at all.
    [[ -s "$cache" ]] || return 1
  fi
  echo "$cache"
}

# Turn a releases JSON blob into: name<TAB>size<TAB>url
# The API answer is one long line, so we split on commas first; every field
# we need is a flat scalar, which makes this safe without a JSON parser.
# In a release asset object "size" always precedes "browser_download_url",
# so tracking the most recent size is enough to pair them up.
proton_parse_assets() {   # proton_parse_assets <json-file> <glob>
  local json="$1" glob="$2"
  tr ',' '\n' < "$json" \
  | awk -v glob="$glob" '
      /"size"[[:space:]]*:/ {
        s = $0; sub(/.*"size"[[:space:]]*:[[:space:]]*/, "", s)
        gsub(/[^0-9]/, "", s); size = s; next
      }
      /"browser_download_url"[[:space:]]*:/ {
        u = $0
        sub(/.*"browser_download_url"[[:space:]]*:[[:space:]]*"/, "", u)
        sub(/".*/, "", u)
        n = u; sub(/.*\//, "", n)
        if (n ~ /\.(sha512sum|sha256sum|txt|md)$/) next
        # translate the shell glob into an anchored regex
        g = glob; gsub(/\./, "\\.", g); gsub(/\*/, ".*", g)
        if (n ~ ("^" g "$")) print n "\t" size "\t" u
      }'
}

# Directory name a tarball unpacks into. GE-Proton tarballs use the tag
# verbatim; the Wine-GE assets are named wine-lutris-GE-ProtonX-Y-x86_64
# but unpack into lutris-GE-ProtonX-Y-x86_64, so only the "wine-" prefix
# comes off. Getting this wrong means the listing shows a build as
# available when it is already installed.
proton_build_name() {   # proton_build_name <asset filename>
  local n="$1"
  n=${n%.tar.gz}; n=${n%.tar.xz}; n=${n%.tar.zst}
  n=${n#wine-}
  printf '%s\n' "$n"
}

proton_installed_in() {   # proton_installed_in <dir> -> one name per line
  local d="$1" e
  [[ -d "$d" ]] || return 0
  for e in "$d"/*; do
    [[ -d "$e" ]] || continue
    basename "$e"
  done
  return 0
}

proton_dir_size() {
  du -sh "$1" 2>/dev/null | cut -f1 || echo "?"
}

# ---- listing -----------------------------------------------------------
# Two line shapes, both 7 fields, discriminated on field 2:
#   PRT|installed|<track>|<name>|<target>|<size>|<path>
#   PRT|remote|<track>|<name>|<target>|<size-bytes>|<url>
# A "remote" line is emitted once per applicable present target, so the
# frontend can offer "install into Steam" and "install into Lutris" as
# separate actions without knowing anything about the track layout.
cmd_proton() {
  local entry track repo glob targets t json name size url built
  local -a remote_names=()

  for entry in "${PROTON_TRACKS[@]}"; do
    IFS='|' read -r track repo glob targets <<<"$entry"

    # -- what is already on disk
    local dir n cur
    for t in ${targets//,/ }; do
      proton_target_present "$t" || continue
      dir=$(proton_target_dir "$t") || continue
      # Which build this launcher currently defaults to. Emitted even when
      # it is empty, so the page can say "still on stock Proton" rather than
      # leaving the user to guess why nothing changed after installing.
      cur=$(compat_current "$t")
      # A launcher can be configured to use a build that has since been
      # deleted — it then silently falls back to its stock Proton/Wine,
      # which looks exactly like "my setting did nothing".
      local dstate=none
      if [[ -n "$cur" ]]; then
        if [[ -d "$dir/$cur" ]]; then dstate=ok; else dstate=missing; fi
      fi
      printf 'PRT|default|%s|%s|%s|-|%s\n' "$track" "${cur:-}" "$t" "$dstate"
      while IFS= read -r n; do
        [[ -n "$n" ]] || continue
        printf 'PRT|installed|%s|%s|%s|%s|%s\n' \
          "$track" "$n" "$t" "$(proton_dir_size "$dir/$n")" "$dir/$n"
      done < <(proton_installed_in "$dir")
    done

    # -- what GitHub offers
    json=$(proton_fetch_releases "$repo") || {
      printf 'PRT|error|%s|-|-|-|Could not reach the GitHub releases API\n' "$track"
      continue
    }
    remote_names=()
    while IFS=$'\t' read -r name size url; do
      [[ -n "$name" ]] || continue
      built=$(proton_build_name "$name")
      # one release can ship several matching assets; first wins
      [[ " ${remote_names[*]} " == *" $built "* ]] && continue
      remote_names+=("$built")
      for t in ${targets//,/ }; do
        proton_target_present "$t" || continue
        printf 'PRT|remote|%s|%s|%s|%s|%s\n' "$track" "$built" "$t" "$size" "$url"
      done
    done < <(proton_parse_assets "$json" "$glob")
  done
  return 0
}

# Newest remote build for a track (used by the plan text and Overview)
proton_latest_remote() {   # proton_latest_remote <track>
  local repo glob json
  repo=$(proton_track_field "$1" 2) || return 1
  glob=$(proton_track_field "$1" 3) || return 1
  json=$(proton_fetch_releases "$repo") || return 1
  local name size url
  while IFS=$'\t' read -r name size url; do
    [[ -n "$name" ]] && { proton_build_name "$name"; return 0; }
  done < <(proton_parse_assets "$json" "$glob")
  return 1
}

proton_remote_url() {   # proton_remote_url <track> <build-name>
  local repo glob json name size url
  repo=$(proton_track_field "$1" 2) || return 1
  glob=$(proton_track_field "$1" 3) || return 1
  json=$(proton_fetch_releases "$repo") || return 1
  while IFS=$'\t' read -r name size url; do
    [[ "$(proton_build_name "$name")" == "$2" ]] && { printf '%s\n' "$url"; return 0; }
  done < <(proton_parse_assets "$json" "$glob")
  return 1
}

# The matching checksum asset, if the release published one.
proton_remote_sum_url() {   # proton_remote_sum_url <track> <build-name>
  local repo json url
  repo=$(proton_track_field "$1" 2) || return 1
  json=$(proton_fetch_releases "$repo") || return 1
  tr ',' '\n' < "$json" \
    | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep -F "/$2" | grep -E '\.sha512sum$' | head -1
  return 0
}

# ---- install -----------------------------------------------------------

plan_proton_install() {   # plan_proton_install <track> <build> <target>
  local track="${1:-}" build="${2:-}" target="${3:-}"
  echo "== Plan: install compatibility tool =="
  [[ -n "$track" && -n "$build" && -n "$target" ]] || {
    echo "Nothing selected."; return 0; }
  local dir; dir=$(proton_target_dir "$target") || { echo "Unknown target '$target'."; return 0; }
  local url; url=$(proton_remote_url "$track" "$build") || {
    echo "Could not find a download for $build — try Refresh (GitHub may be rate-limiting)."
    return 0; }
  local sum; sum=$(proton_remote_sum_url "$track" "$build")
  echo "Build:    $build   ($track)"
  echo "For:      $(proton_target_label "$target")"
  echo "Into:     $dir"
  echo "Download: $url"
  if [[ -n "$sum" ]]; then
    echo "Verify:   sha512sum published with the release"
  else
    echo "Verify:   no checksum published for this release — download unverified"
  fi
  if [[ -d "$dir/$build" ]]; then
    echo ""
    echo "! $build is already there. It will be replaced with a fresh copy."
  fi
  echo ""
  local cur; cur=$(compat_current "$target")
  echo "Currently: ${cur:-the launcher stock Proton/Wine}"
  echo ""
  if [[ $RUN_USER != root ]]; then
    echo "Runs as $RUN_USER, not root — Steam ignores root-owned entries here."
  fi
  echo ""
  echo "NOTE: installing only makes the build available. Nothing switches to"
  echo "it until it is set as the default (or picked per game), which is a"
  echo "separate step."
  case "$target" in
    steam)  echo "Pick it per game: Properties -> Compatibility -> Force a specific tool." ;;
    lutris) echo "Pick it in Lutris: game -> Configure -> Runner options -> Wine version." ;;
    heroic-*) echo "Pick it in Heroic: game -> Settings -> Wine/Proton version." ;;
  esac
  echo "Restart the launcher afterwards — none of them rescan while running."
}

apply_proton_install() {   # apply_proton_install <track> <build> <target> [default]
  local track="${1:-}" build="${2:-}" target="${3:-}" makedefault="${4:-}"
  [[ -n "$track" && -n "$build" && -n "$target" ]] || {
    echo ":: usage: apply proton-install <track> <build> <target>"; return 1; }
  # Guard the one field that becomes a path component.
  [[ "$build" =~ ^[A-Za-z0-9._-]+$ ]] || { echo ":: invalid build name."; return 1; }

  local dir; dir=$(proton_target_dir "$target") || { echo ":: unknown target '$target'."; return 1; }
  local url; url=$(proton_remote_url "$track" "$build") || {
    echo ":: no download found for $build."; return 1; }

  run_user mkdir -p "$dir" || { echo ":: cannot create $dir"; return 1; }

  local tmp="$PROTON_CACHE/dl"
  run_user mkdir -p "$tmp"
  local file="$tmp/${url##*/}"

  echo ":: Downloading $build"
  echo "   $url"
  if ! run_user curl -fL --progress-bar --max-time 1800 -o "$file" "$url"; then
    echo ":: Download failed."
    run_user rm -f "$file"
    return 1
  fi

  local sum; sum=$(proton_remote_sum_url "$track" "$build")
  if [[ -n "$sum" ]]; then
    echo ":: Verifying sha512sum"
    local want got
    want=$(run_user curl -fsSL --max-time 30 "$sum" 2>/dev/null | awk 'NR==1{print $1}')
    got=$(sha512sum "$file" 2>/dev/null | awk '{print $1}')
    if [[ -z "$want" ]]; then
      echo ":: Could not fetch the checksum — refusing to install unverified."
      run_user rm -f "$file"
      return 1
    elif [[ "$want" != "$got" ]]; then
      echo ":: CHECKSUM MISMATCH — the download is corrupt or tampered with."
      echo "   expected $want"
      echo "   got      $got"
      run_user rm -f "$file"
      return 1
    fi
    echo ":: Checksum OK"
  else
    echo ":: No checksum published for this release — installing unverified."
  fi

  # Ask the tarball where it will land rather than inferring it from the
  # asset name — that inference is exactly what differs between the two
  # tracks, and a wrong guess leaves an orphaned directory behind.
  local topdir
  topdir=$(tar -tf "$file" 2>/dev/null | head -1 | cut -d/ -f1)
  if [[ -z "$topdir" || "$topdir" == /* || "$topdir" == *..* ]]; then
    echo ":: Refusing to extract: the archive has no single safe top-level directory."
    run_user rm -f "$file"
    return 1
  fi

  # Replace rather than merge: a half-overwritten runner is worse than none.
  if [[ -d "$dir/$topdir" ]]; then
    echo ":: Replacing existing $topdir"
    run_user rm -rf "$dir/$topdir"
  fi

  echo ":: Extracting into $dir"
  if ! run_user tar -xf "$file" -C "$dir"; then
    echo ":: Extraction failed — removing partial directory."
    run_user rm -rf "$dir/$topdir"
    run_user rm -f "$file"
    return 1
  fi
  run_user rm -f "$file"

  log_change "installed $track build $topdir into $dir ($(proton_target_label "$target"))"
  echo ":: $topdir installed for $(proton_target_label "$target")."

  # Installing only makes a build AVAILABLE. Every launcher keeps its own
  # separate setting for which build a game runs on, and none of them move
  # to a newer one by themselves — so without this step the new build sits
  # there unused and nothing appears to have happened.
  if [[ "$makedefault" == default ]]; then
    echo ""
    apply_compat_default "$target" "$topdir" || return 1
  else
    local cur; cur=$(compat_current "$target")
    echo ""
    if [[ "$cur" == "$topdir" ]]; then
      echo ":: $(proton_target_label "$target") already defaults to it."
    else
      echo ":: NOT selected yet — $(proton_target_label "$target") still uses"
      echo "::   ${cur:-its own stock Proton/Wine}."
      echo ":: Installing a build never switches anything by itself. Use"
      echo "::   akari-setup apply compat-default $target $topdir"
      echo ":: or the Use by default button on the Proton page."
    fi
  fi
  echo ":: Restart the launcher to pick it up."
}

# ---- remove / prune ----------------------------------------------------

plan_proton_remove() {   # plan_proton_remove <build> <target>
  local build="${1:-}" target="${2:-}"
  echo "== Plan: remove compatibility tool =="
  local dir; dir=$(proton_target_dir "$target") || { echo "Unknown target."; return 0; }
  [[ -d "$dir/$build" ]] || { echo "$build is not installed for $(proton_target_label "$target")."; return 0; }
  echo "Build:  $build"
  echo "Path:   $dir/$build"
  echo "Frees:  $(proton_dir_size "$dir/$build")"
  echo ""
  echo "Games still configured to use it fall back to the launcher's default"
  echo "Proton/Wine. Prefixes in compatdata are untouched."
}

apply_proton_remove() {   # apply_proton_remove <build> <target>
  local build="${1:-}" target="${2:-}"
  [[ "$build" =~ ^[A-Za-z0-9._-]+$ ]] || { echo ":: invalid build name."; return 1; }
  local dir; dir=$(proton_target_dir "$target") || { echo ":: unknown target."; return 1; }
  [[ -d "$dir/$build" ]] || { echo ":: $build is not installed there."; return 1; }
  local size; size=$(proton_dir_size "$dir/$build")
  run_user rm -rf "$dir/$build" || { echo ":: Removal failed."; return 1; }
  log_change "removed compatibility tool $build from $dir (freed $size)"
  echo ":: Removed $build ($size freed)."
}

# Keep the N newest builds per target; each GE build is ~1.5 GB, so this is
# the difference between a tidy directory and a full disk.
proton_prune_list() {   # proton_prune_list <keep> -> "<target>\t<build>" per line
  local keep="${1:-2}" entry track targets t dir
  for entry in "${PROTON_TRACKS[@]}"; do
    IFS='|' read -r track _ _ targets <<<"$entry"
    for t in ${targets//,/ }; do
      proton_target_present "$t" || continue
      dir=$(proton_target_dir "$t") || continue
      [[ -d "$dir" ]] || continue
      local -a builds=()
      while IFS= read -r n; do [[ -n "$n" ]] && builds+=("$n"); done \
        < <(proton_installed_in "$dir" | sort -V)
      local total=${#builds[@]} i
      (( total > keep )) || continue
      for (( i = 0; i < total - keep; i++ )); do
        printf '%s\t%s\n' "$t" "${builds[i]}"
      done
    done
  done
  return 0
}

plan_proton_prune() {   # plan_proton_prune [keep]
  local keep="${1:-2}"
  echo "== Plan: prune old compatibility tools =="
  echo "Keeping the $keep newest build(s) per launcher."
  echo ""
  local t b dir any=0
  while IFS=$'\t' read -r t b; do
    [[ -n "$t" ]] || continue
    any=1
    dir=$(proton_target_dir "$t")
    printf '  remove  %-32s %-16s %s\n' "$b" "$(proton_target_label "$t")" \
      "$(proton_dir_size "$dir/$b")"
  done < <(proton_prune_list "$keep")
  (( any )) || echo "  nothing to prune"
}

apply_proton_prune() {   # apply_proton_prune [keep]
  local keep="${1:-2}" t b dir any=0
  while IFS=$'\t' read -r t b; do
    [[ -n "$t" ]] || continue
    dir=$(proton_target_dir "$t")
    echo ":: Removing $b ($(proton_target_label "$t"))"
    run_user rm -rf "$dir/$b" && any=1
    log_change "pruned compatibility tool $b from $dir"
  done < <(proton_prune_list "$keep")
  if (( any )); then
    echo ":: Prune complete."
  else
    echo ":: Nothing to prune."
  fi
}

# ---- selecting a build -------------------------------------------------
# Installing a build only makes it AVAILABLE. Every launcher keeps a
# separate setting for which one a game actually runs on, and none of them
# switch by themselves — so a fresh GE-Proton sits unused until something
# points at it. These functions are that pointer.

steam_configvdf() {   # Steam's global config.vdf, or ""
  local base
  for base in "$RUN_HOME/.steam/root" "$RUN_HOME/.local/share/Steam" \
              "$RUN_HOME/.steam/steam"; do
    [[ -r "$base/config/config.vdf" ]] && { echo "$base/config/config.vdf"; return; }
  done
  return 0
}

# The build a target currently defaults to, or "" if it is on its own stock
# Proton/Wine.
compat_current() {   # compat_current <target>
  case "$1" in
    steam)
      local cfg; cfg=$(steam_configvdf)
      [[ -n "$cfg" ]] || return 0
      vdf_py compat-get "$cfg" 2>/dev/null \
        | awk -F'|' '$2=="0" {print $3; exit}' ;;
    lutris|heroic-proton|heroic-wine)
      games_py default-get "$1" 2>/dev/null ;;
  esac
  return 0
}

plan_compat_default() {   # plan_compat_default <target> <build>
  local target="${1:-}" build="${2:-}"
  echo "== Plan: use $build by default =="
  local dir; dir=$(proton_target_dir "$target") || { echo "Unknown target '$target'."; return 0; }
  if [[ ! -d "$dir/$build" ]]; then
    echo "$build is not installed for $(proton_target_label "$target") — install it first."
    return 0
  fi
  local cur; cur=$(compat_current "$target")
  echo "Launcher: $(proton_target_label "$target")"
  echo "Current:  ${cur:-<the stock Proton/Wine the launcher ships with>}"
  echo "New:      $build"
  case "$target" in
    steam)
      echo "File:     $(steam_configvdf) (backed up first)"
      echo ""
      echo "This is the same switch as Steam > Settings > Compatibility >"
      echo "'Enable Steam Play for all other titles'. Games with a per-game"
      echo "override keep it — set those individually from the Games page."
      if steam_running; then
        echo ""
        echo "! Steam is RUNNING and rewrites config.vdf on exit, so the change"
        echo "  would be lost. Close Steam first; apply refuses while it runs."
      fi ;;
    lutris)
      echo "File:     $RUN_HOME/.config/lutris/runners/wine.yml (backed up first)"
      echo ""
      echo "Applies to games using the default Wine version. Games pinned to a"
      echo "specific version keep it." ;;
    heroic-*)
      echo "File:     $RUN_HOME/.config/heroic/config.json (backed up first)"
      echo ""
      echo "Sets Heroic's default Wine/Proton version for new and unpinned games." ;;
  esac
  echo ""
  echo "Already-running games are unaffected — this takes effect at next launch."
}

apply_compat_default() {   # apply_compat_default <target> <build>
  local target="${1:-}" build="${2:-}"
  [[ -n "$target" && -n "$build" ]] || { echo ":: usage: apply compat-default <target> <build>"; return 1; }
  [[ "$build" =~ ^[A-Za-z0-9._-]+$ ]] || { echo ":: invalid build name."; return 1; }
  local dir; dir=$(proton_target_dir "$target") || { echo ":: unknown target '$target'."; return 1; }
  [[ -d "$dir/$build" ]] || { echo ":: $build is not installed for $(proton_target_label "$target")."; return 1; }

  case "$target" in
    steam)
      local cfg; cfg=$(steam_configvdf)
      [[ -n "$cfg" ]] || { echo ":: Steam's config.vdf not found — start Steam once first."; return 1; }
      if steam_running; then
        echo ":: Steam is running — it rewrites config.vdf on exit."
        echo ":: Close Steam and try again."
        return 1
      fi
      local bak="${cfg}.akari.bak"
      run_user cp "$cfg" "$bak"
      echo ":: Backup: $bak"
      local out
      if ! out=$(vdf_py compat-set "$cfg" 0 "$build"); then
        echo ":: Edit failed — restoring backup."
        run_user cp "$bak" "$cfg"
        return 1
      fi
      log_change "set Steam default compatibility tool to $build (backup: $bak)"
      echo ":: Steam will use $build for every title without its own override."
      echo ":: Start Steam to pick it up." ;;
    lutris|heroic-proton|heroic-wine)
      local gout
      if ! gout=$(games_py default-set "$target" "$build"); then
        echo ":: Edit failed: ${gout#ERR|}"
        return 1
      fi
      [[ $gout == ERR\|* ]] && { echo ":: ${gout#ERR|}"; return 1; }
      log_change "set $(proton_target_label "$target") default runner to $build"
      echo ":: $(proton_target_label "$target") will use $build by default."
      echo ":: Restart the launcher to pick it up." ;;
    *) echo ":: unknown target '$target'."; return 1 ;;
  esac
}
