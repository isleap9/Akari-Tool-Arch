# Akari Tool Linux — v0.1 skeleton

Gaming setup tool for vanilla Arch Linux. Three layers, three files:

```
akari-tool-linux/
├── backend/akari-setup.sh   BASH   — all real logic (check / plan / apply)
├── ui/Main.qml              QML    — Material dark UI, red accent
└── main.py                  PYTHON — ~120 lines of glue (QProcess bridge)
```

## Run it (on your Arch machine)

```bash
sudo pacman -S pyside6        # only runtime dependency besides bash
cd akari-tool-linux
python main.py
```

The backend also works with no GUI at all:

```bash
./backend/akari-setup.sh check          # status report
./backend/akari-setup.sh plan gaming    # dry-run: what would be installed
./backend/akari-setup.sh apply gaming   # do it
./backend/akari-setup.sh apply tweaks   # vm.max_map_count + gamemode group
```

## How the layers talk

- On launch, Python runs `akari-setup.sh check`. The script prints
  `key|state|detail` lines; Python parses them into `bridge.status`,
  which the QML cards read (green/amber/red chips).
- Card buttons call `bridge.run("apply", "gaming")` etc. The UI swaps to
  the live log view and streams the script's stdout as it runs.
- When an apply finishes, `check` re-runs automatically so the cards
  reflect the new state.

## Design notes

- **Idempotent**: every apply is safe to run twice (`pacman --needed`,
  multilib grep-before-edit, sysctl file overwrite).
- **Every change is logged** to `~/.local/state/akari-tool/changes.log`,
  and `pacman.conf` is backed up before editing. This is the
  reliability story vs. linutil.
- **Package lists are data** (top of the .sh file), derived from
  CachyOS's `cachyos-gaming-meta` + `cachyos-gaming-applications`,
  translated to vanilla Arch (wine-staging instead of wine-cachyos,
  ProtonGE via optional AUR, etc.).
- **AUR is never a hard dependency** — extras are skipped with a notice
  if no paru/yay is found.
- **sudo is per-command**, the app itself never runs as root.

## Roadmap hooks already in place

- Porting the GUI host to Rust = rewrite `main.py` only (~same size in
  Rust with qmetaobject/cxx-qt). QML + bash are untouched.
- Sidebar nav items are stubs — Overview is the only page wired up.
  Gaming / GPU / Tweaks / Change Log pages come next.
- For AUR distribution: PKGBUILD installs the three files +
  a .desktop entry; depends on `pyside6`.

## Known TODOs before real use

- NVIDIA driver choice is simplified (`nvidia` package). Add the
  Turing+ → `nvidia-open`, custom-kernel → `nvidia-dkms` branching.
- `apply` uses `--noconfirm` for GUI flow; add a `--confirm` mode for
  standalone CLI use.
- pacman needs a full `-Syu` consideration before installing on a stale
  system (partial-upgrade risk) — currently only `-Sy` after enabling
  multilib.
