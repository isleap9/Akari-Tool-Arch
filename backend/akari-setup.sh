#!/usr/bin/env bash
#
# akari-setup.sh — Akari Tool Linux backend
# Architecture: check -> plan -> apply. Idempotent. Usable standalone or from the GUI.
#
# Usage:
#   ./akari-setup.sh check            # machine-readable status (used by GUI)
#   ./akari-setup.sh plan gaming      # show what 'apply gaming' would do
#   ./akari-setup.sh apply gaming     # install gaming packages
#   ./akari-setup.sh apply multilib   # enable multilib repo
#   ./akari-setup.sh apply tweaks     # conservative perf tweaks
#
set -euo pipefail


# ---------------------------------------------------------------- modules
# All logic lives in lib/, split by concern and sourced in order.
# This file keeps only: shell options, module loading, version, dispatch.
AKARI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
for _mod in "$AKARI_LIB"/*.sh; do
  # shellcheck source=/dev/null
  source "$_mod"
done
unset _mod

# ---------------------------------------------------------------- dispatch

AKARI_VERSION="0.5.1"

case "${1:-}" in
  --version|-V) echo "akari-setup $AKARI_VERSION" ;;
  --help|-h)
    cat <<'HELP'
akari-setup — Akari Tool Linux backend (works standalone, no GUI needed)

  check                          machine-readable system status
  packages                       gaming package list with install state
  kernels                        available kernels with install/running state
  diagnose                       functional tests of the gaming stack
  apps                           everything the user installed (for the Apps page)
  restore-list                   backups available to restore
  steam-games                    Steam library with current launch options
  games                          all installed games (Steam, Lutris, Heroic)
  proton                         Proton-GE / Wine-GE builds, installed and available
  log                            everything this tool changed
  plan  <target>                 dry-run: what an apply would do
  apply <target>                 do it (uses sudo per command)

  targets: gaming, multilib, tweaks, sysupdate, all,
           paru, mirrors, cleanup, snapshot, flatpak-setup, flatpak <appid...>, self-update,
           kernel <name>, remove-kernel <name>, launchopts <appid> "<options>",
           gameopts <source> <id> "<options>",
           gamerunner <source> <id> <build>, compat-default <target> <build>,
           proton-install <track> <build> <target> [default],
           proton-remove <build> <target>, proton-prune [keep],
           selected <pkg...>, remove <pkg...>, restore <backup-id>
HELP
    ;;
  check)    cmd_check ;;
  packages) cmd_packages ;;
  kernels)  cmd_kernels ;;
  diagnose) cmd_diagnose ;;
  apps)     cmd_apps ;;
  restore-list) cmd_restore_list ;;
  steam-games)  cmd_steam_games ;;
  games)    cmd_games ;;
  proton)   cmd_proton ;;
  log)      cmd_log ;;
  plan)   case "${2:-gaming}" in
            gaming)        plan_gaming ;;
            multilib)      plan_multilib ;;
            tweaks)        plan_tweaks ;;
            kernel)        plan_kernel "${3:-}" ;;
            remove-kernel) plan_remove_kernel "${3:-}" ;;
            sysupdate)     plan_sysupdate ;;
            paru)          plan_paru ;;
            snapshot)      plan_snapshot ;;
            flatpak-setup) plan_flatpak_setup ;;
            self-update)   plan_self_update ;;
            launchopts)    plan_launchopts "${3:-}" "${4:-}" ;;
            gameopts)      plan_gameopts "${3:-}" "${4:-}" "${5:-}" ;;
            proton-install) plan_proton_install "${3:-}" "${4:-}" "${5:-}" ;;
            compat-default) plan_compat_default "${3:-}" "${4:-}" ;;
            gamerunner)     plan_gamerunner "${3:-}" "${4:-}" "${5:-}" ;;
            proton-remove)  plan_proton_remove "${3:-}" "${4:-}" ;;
            proton-prune)   plan_proton_prune "${3:-2}" ;;
            mirrors)       plan_mirrors ;;
            cleanup)       plan_cleanup ;;
            all)           plan_all ;;
            restore)       plan_restore "${3:-}" ;;
            remove)        shift 2; plan_remove "$@" ;;
            *) echo "unknown plan target"; exit 1 ;;
          esac ;;
  apply)  case "${2:-}" in
            gaming)        apply_gaming ;;
            multilib)      apply_multilib ;;
            tweaks)        apply_tweaks ;;
            kernel)        apply_kernel "${3:-}" ;;
            remove-kernel) remove_kernel "${3:-}" ;;
            sysupdate)     apply_sysupdate ;;
            paru)          apply_paru ;;
            snapshot)      apply_snapshot ;;
            flatpak-setup) apply_flatpak_setup ;;
            self-update)   apply_self_update ;;
            launchopts)    apply_launchopts "${3:-}" "${4:-}" ;;
            gameopts)      apply_gameopts "${3:-}" "${4:-}" "${5:-}" ;;
            proton-install) apply_proton_install "${3:-}" "${4:-}" "${5:-}" "${6:-}" ;;
            compat-default) apply_compat_default "${3:-}" "${4:-}" ;;
            gamerunner)     apply_gamerunner "${3:-}" "${4:-}" "${5:-}" ;;
            proton-remove)  apply_proton_remove "${3:-}" "${4:-}" ;;
            proton-prune)   apply_proton_prune "${3:-2}" ;;
            flatpak)       shift 2; apply_flatpak "$@" ;;
            mirrors)       apply_mirrors ;;
            cleanup)       apply_cleanup ;;
            all)           apply_all ;;
            restore)       apply_restore "${3:-}" ;;
            selected)      shift; apply_selected "$@" ;;
            remove)        shift 2; apply_remove "$@" ;;
            *) echo "usage: $0 apply {gaming|multilib|tweaks|kernel <name>|remove-kernel <name>|selected pkg...}"; exit 1 ;;
          esac ;;
  *) echo "usage: $0 {check|packages|kernels|plan gaming|apply {gaming|multilib|tweaks|kernel <name>|selected pkg...}}"; exit 1 ;;
esac
