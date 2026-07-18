#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- restore / undo ------------------------------------------------------
# Every risky edit keeps a .akari.bak next to the original. These commands
# list and restore them. Emits: RST|id|backup_path|original_path|timestamp

akari_backups() {
  local f
  for f in /etc/pacman.conf.akari.bak /etc/mkinitcpio.d/*.akari.bak \
           "$RUN_HOME"/.local/share/Steam/userdata/*/config/localconfig.vdf.akari.bak \
           "$RUN_HOME"/.steam/steam/userdata/*/config/localconfig.vdf.akari.bak; do
    [[ -e "$f" ]] && echo "$f"
  done
  return 0
}

cmd_restore_list() {
  local f orig ts
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    orig=${f%.akari.bak}
    ts=$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")
    printf 'RST|%s|%s|%s|%s\n' "$(basename "$f")" "$f" "$orig" "$ts"
  done < <(akari_backups)
  if command -v snapper &>/dev/null; then
    printf 'RST|snapper|-|-|snapper is active: every pacman operation has pre/post snapshots (snapper list / rollback)\n'
  fi
  return 0
}

find_backup_by_id() {
  local id="$1" f
  while IFS= read -r f; do
    [[ "$(basename "$f")" == "$id" ]] && { echo "$f"; return 0; }
  done < <(akari_backups)
  return 1
}

plan_restore() {
  local id="$1" f orig
  f=$(find_backup_by_id "$id") || { echo "No such backup: $id"; return 1; }
  orig=${f%.akari.bak}
  echo "== Plan: restore $(basename "$orig") =="
  echo "Will do:"
  echo "  1. Save the CURRENT $orig as ${orig}.before-restore"
  echo "  2. Copy the backup ($f, from $(date -r "$f" '+%Y-%m-%d %H:%M')) over $orig"
  [[ "$orig" == /etc/pacman.conf ]] && \
    echo "  3. Run pacman -Sy to resync repositories"
  echo ""
  echo "Nothing is deleted — the restore itself is undoable."
}

apply_restore() {
  local id="$1" f orig
  f=$(find_backup_by_id "$id") || { echo "No such backup: $id" >&2; return 1; }
  orig=${f%.akari.bak}
  echo ":: Saving current $orig as ${orig}.before-restore"
  run_root cp -a "$orig" "${orig}.before-restore"
  echo ":: Restoring $orig from backup"
  run_root cp -a "$f" "$orig"
  log_change "restored $orig from $f (previous state saved as ${orig}.before-restore)"
  if [[ "$orig" == /etc/pacman.conf ]]; then
    echo ":: Resyncing repositories"
    run_root pacman -Sy
  fi
  echo ":: Restore complete."
}

cmd_log() {
  if [[ -s "$LOGFILE" ]]; then
    cat "$LOGFILE"
  else
    echo "No changes recorded yet."
    echo "Every change Akari Tool makes to this system will be listed here."
  fi
}

