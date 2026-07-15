# Akari Tool Linux — v0.1

Gaming setup tool for vanilla Arch Linux.

## Structure

```
akari-tool-linux/
├── backend/
│   └── akari-setup.sh        # ALL system logic (check / plan / apply) — works standalone
├── akari/                    # Python host package (glue only, no logic)
│   ├── app.py                #   Qt app + QML engine bootstrap
│   ├── bridge.py             #   QProcess bridge to the bash backend
│   └── __main__.py           #   `python -m akari`
├── ui/
│   ├── Main.qml              # window shell: sidebar, header, page routing
│   ├── components/           # reusable widgets (QML module)
│   │   ├── qmldir            #   module definition
│   │   ├── Theme.qml         #   singleton: all colors & metrics live here
│   │   ├── NavItem.qml
│   │   ├── StatusCard.qml
│   │   └── SectionLabel.qml
│   └── pages/
│       ├── OverviewPage.qml  # status card grid
│       └── LogPage.qml       # live backend output
└── main.py                   # entry point (same as `python -m akari`)
```

## Run

```bash
sudo pacman -S pyside6
python main.py        # or: python -m akari
```

Backend standalone:

```bash
./backend/akari-setup.sh check
./backend/akari-setup.sh plan gaming
./backend/akari-setup.sh apply gaming|multilib|tweaks
```

## Conventions

- **All system logic goes in the bash backend.** Python never runs pacman.
- **All colors/metrics go in `Theme.qml`.** No hex codes in pages/components.
- **New page** = new file in `ui/pages/` + a NavItem + a StackLayout entry in Main.qml.
- **New reusable widget** = file in `ui/components/` + a line in `qmldir`.
- Backend `check` protocol: one `key|state|detail` line per check,
  state ∈ ok|warn|fail. The bridge parses these into `bridge.status`.

## TODO

- Sidebar navigation between pages (NavItems are visual-only; Overview is
  the single wired page — add a `currentPage` state in Main.qml)
- Gaming page: per-package checkbox list (read package sets from backend)
- NVIDIA branching: nvidia-open (Turing+) / nvidia-dkms (custom kernels)
- Polkit/pkexec prompt instead of relying on cached sudo
- `--confirm` mode for CLI use (currently --noconfirm for GUI flow)
- PKGBUILD for AUR distribution
