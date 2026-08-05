#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- unified games library (Games page) --------------------------------
# Collects installed games from Steam, Lutris and Heroic into one list and
# lets the Launch Options builder write its string back to whichever
# launcher owns the game.
#
# Reading is per-launcher and completely different in each case (VDF/ACF,
# SQLite, JSON), so it lives behind one embedded python3 helper for Lutris
# and Heroic, while Steam reuses the VDF machinery already in 80-steam.sh.
# python3 is a hard requirement of the backend anyway (see vdf_py) and its
# stdlib covers sqlite3 and json, so this adds no new dependency.
#
# Protocol — always 8 fields:
#   GAM|<source>|<id>|<name>|<state>|<size>|<runner>|<options>
# <name> and <options> are percent-encoded, because game titles and launch
# strings both contain '|' sooner or later (Divinity: Original Sin, and
# every shell pipe someone puts in a launch string).
# A source that is present but unreadable emits one line with
# state=unavailable and the reason in <options>, so the frontend can show
# "why is this empty" instead of nothing at all.

# ---- launcher liveness -------------------------------------------------
# Every launcher here caches its game config in memory and rewrites it on
# exit, so an edit made while it runs is silently thrown away. Matching on
# the process NAME and not the whole command line matters: a bare
# `pgrep -f heroic` also matches an editor that happens to have a Heroic
# config open, and then the tool refuses to work for no reason.
launcher_running() {   # launcher_running <steam|lutris|heroic>
  case "$1" in
    steam)  steam_running ;;
    lutris) pgrep -x lutris &>/dev/null \
              || pgrep -f '(^|/)(python[0-9.]*[[:space:]]+)?[^[:space:]]*/lutris$' &>/dev/null ;;
    heroic) pgrep -ix 'heroic|heroic-games-launcher|heroic-run' &>/dev/null ;;
    *) return 1 ;;
  esac
}

# ---- field encoding ----------------------------------------------------
# Order matters: encode '%' first, decode it last, or a literal "%7C" in a
# game title round-trips into a pipe.
gam_enc() { local s=${1//\%/%25}; printf '%s\n' "${s//|/%7C}"; }
gam_dec() { local s=${1//%7C/|}; printf '%s\n' "${s//%25/%}"; }

gam_human() {   # bytes -> human, tolerant of empty/garbage input
  local b=${1:-0}
  [[ $b =~ ^[0-9]+$ ]] || { echo "-"; return; }
  (( b == 0 )) && { echo "-"; return; }
  numfmt --to=iec-i --suffix=B --format='%.1f' "$b" 2>/dev/null || echo "-"
}

# ---- Steam -------------------------------------------------------------

# Every library folder Steam knows about, not just the default one — most
# people keep the big games on a second drive.
steam_libraries() {
  local base vdf
  for base in "$RUN_HOME/.local/share/Steam" "$RUN_HOME/.steam/steam" \
              "$RUN_HOME/.steam/root"; do
    vdf="$base/steamapps/libraryfolders.vdf"
    [[ -r "$vdf" ]] || continue
    echo "$base/steamapps"
    sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$vdf" \
      | while IFS= read -r p; do
          [[ -d "$p/steamapps" ]] && echo "$p/steamapps"
        done
  done | awk '!seen[$0]++'
}

# Runtimes and tools ship appmanifest files too. Filtering them by name is
# more durable than a hardcoded appid list, which goes stale every time
# Valve ships a new runtime.
steam_is_tool_name() {
  case "$1" in
    Proton*|"Steam Linux Runtime"*|Steamworks*|"Steam Controller"*|\
    SteamVR*|"Proton Experimental"|"Proton Hotfix") return 0 ;;
  esac
  return 1
}

# Per-game compatibility tool override, from config.vdf's CompatToolMapping.
# Nested-block awk rather than a real parser: we only need one leaf value
# per appid and the block shape has been stable for years.
steam_compat_map() {   # -> "<appid>\t<tool>" per line
  local base cfg
  for base in "$RUN_HOME/.steam/root" "$RUN_HOME/.local/share/Steam" \
              "$RUN_HOME/.steam/steam"; do
    cfg="$base/config/config.vdf"
    [[ -r "$cfg" ]] || continue
    awk '
      /"CompatToolMapping"/ { inmap = 1; depth = 0; next }
      inmap {
        if ($0 ~ /\{/) { depth++ }
        if ($0 ~ /"([0-9]+)"/ && $0 !~ /"name"/ && depth <= 1) {
          match($0, /"[0-9]+"/); app = substr($0, RSTART+1, RLENGTH-2)
        }
        if ($0 ~ /"name"/) {
          v = $0
          sub(/.*"name"[^"]*"/, "", v); sub(/".*/, "", v)
          if (app != "" && v != "") print app "\t" v
        }
        if ($0 ~ /\}/) { depth--; if (depth < 0) inmap = 0 }
      }' "$cfg"
    return 0
  done
  return 0
}

games_steam() {
  local cfg; cfg=$(steam_localconfig)
  if [[ -z "$cfg" ]]; then
    # Steam installed but never logged in — worth saying so explicitly.
    if is_installed steam; then
      printf 'GAM|steam|-|-|unavailable|-|-|%s\n' \
        "$(gam_enc 'Steam is installed but has no user data yet — log in once, then refresh.')"
    fi
    return 0
  fi

  # appid -> current launch options, straight from the existing SGM listing
  local optmap; optmap=$(mktemp) || return 0
  cmd_steam_games 2>/dev/null | awk -F'|' '$1=="SGM"{print $2"\t"$4}' > "$optmap"
  local compat; compat=$(mktemp) || { rm -f "$optmap"; return 0; }
  steam_compat_map > "$compat" 2>/dev/null || true

  # A stale appmanifest left behind after moving a game between drives makes
  # the same appid appear in two libraries; list it once.
  local seen=" "
  local lib m appid name bytes
  while IFS= read -r lib; do
    for m in "$lib"/appmanifest_*.acf; do
      [[ -r "$m" ]] || continue
      appid=$(sed -n 's/^[[:space:]]*"appid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$m" | head -1)
      name=$(sed -n 's/^[[:space:]]*"name"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$m" | head -1)
      bytes=$(sed -n 's/^[[:space:]]*"SizeOnDisk"[[:space:]]*"\([0-9]*\)".*/\1/p' "$m" | head -1)
      [[ -n "$appid" && -n "$name" ]] || continue
      steam_is_tool_name "$name" && continue
      [[ $seen == *" $appid "* ]] && continue
      seen+="$appid "
      local opts runner
      opts=$(awk -F'\t' -v id="$appid" '$1==id{print $2; exit}' "$optmap")
      runner=$(awk -F'\t' -v id="$appid" '$1==id{print $2; exit}' "$compat")
      printf 'GAM|steam|%s|%s|installed|%s|%s|%s\n' \
        "$appid" "$(gam_enc "$name")" "$(gam_human "$bytes")" \
        "${runner:--}" "$(gam_enc "${opts:-}")"
    done
  done < <(steam_libraries)
  rm -f "$optmap" "$compat"
  return 0
}

# ---- Lutris + Heroic ---------------------------------------------------
# One helper, two commands. Everything it needs comes in as argv; it never
# reaches outside $HOME and never writes without being told to.

games_py() {   # games_py <list|set-lutris|set-heroic> [args...]
  run_user python3 - "$RUN_HOME" "$@" <<'PYEOF'
import json, os, re, sqlite3, sys

home, cmd = sys.argv[1], sys.argv[2]

def enc(s):
    return str(s or "").replace("%", "%25").replace("|", "%7C")

def human(b):
    try: b = int(b)
    except (TypeError, ValueError): return "-"
    if b <= 0: return "-"
    for u in ("B", "KiB", "MiB", "GiB", "TiB"):
        if b < 1024 or u == "TiB":
            return f"{b:.1f}{u}" if u != "B" else f"{b}B"
        b /= 1024
    return "-"

def emit(src, gid, name, state, size, runner, opts):
    print(f"GAM|{src}|{gid}|{enc(name)}|{state}|{size}|{runner or '-'}|{enc(opts)}")

def unavailable(src, why):
    emit(src, "-", "-", "unavailable", "-", "-", why)

# ---------------------------------------------------------------- lutris
LUTRIS_DATA = os.path.join(home, ".local/share/lutris")
LUTRIS_CFG = os.path.join(home, ".config/lutris/games")

def lutris_yaml_opts(configpath):
    """Read back the launch string Akari wrote, from the managed block.

    A full YAML parse is not worth a dependency here: we only ever need the
    two keys we ourselves write, and we write them in a fixed shape.
    """
    path = os.path.join(LUTRIS_CFG, f"{configpath}.yml")
    if not os.path.isfile(path):
        return ""
    env, prefix = [], ""
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return ""
    in_system = in_env = False
    for raw in lines:
        if raw[:1] not in (" ", "\t", "") and raw.rstrip().endswith(":"):
            in_system = raw.strip() == "system:"
            in_env = False
            continue
        if not in_system:
            continue
        s = raw.strip()
        indent = len(raw) - len(raw.lstrip())
        if s == "env:":
            in_env = True
            env_indent = indent
            continue
        if in_env and indent <= env_indent:
            in_env = False
        if in_env and ":" in s:
            k, _, v = s.partition(":")
            env.append(f"{k.strip()}={v.strip().strip(chr(39)).strip(chr(34))}")
        elif s.startswith("command_prefix:"):
            prefix = s.split(":", 1)[1].strip().strip("'").strip('"')
    parts = env + ([prefix] if prefix else [])
    return " ".join(parts + ["%command%"]) if parts else ""

def lutris_game_runner(configpath):
    """The Wine build this game is pinned to, else the Lutris-wide default."""
    path = os.path.join(LUTRIS_CFG, f"{configpath}.yml")
    if os.path.isfile(path):
        seen = False
        for raw in open(path, encoding="utf-8", errors="replace"):
            st = raw.strip()
            if not raw.startswith((" ", "\t")) and st.endswith(":"):
                seen = (st == "wine:")
            if seen and st.startswith("version:"):
                return st.split(":", 1)[1].strip().strip("'").strip('"')
    return default_get("lutris")


def lutris_list():
    db = os.path.join(LUTRIS_DATA, "pga.db")
    if not os.path.isfile(db):
        if os.path.isdir(LUTRIS_DATA):
            unavailable("lutris", "Lutris has no game database yet — add a game, then refresh.")
        return
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = con.execute(
            "SELECT slug, name, runner, configpath, directory, installed "
            "FROM games WHERE installed = 1"
        ).fetchall()
        con.close()
    except sqlite3.Error as e:
        unavailable("lutris", f"Could not read Lutris database: {e}")
        return
    for slug, name, runner, configpath, directory, _inst in rows:
        cfg = configpath or slug
        size = "-"
        if directory and os.path.isdir(directory):
            total = 0
            for root, _d, files in os.walk(directory):
                for f in files:
                    try: total += os.path.getsize(os.path.join(root, f))
                    except OSError: pass
                if total > 200 * 1024 ** 3:   # stop measuring absurd trees
                    break
            size = human(total)
        emit("lutris", cfg, name or slug, "installed", size,
             lutris_game_runner(cfg) or runner or "-", lutris_yaml_opts(cfg))

def lutris_set(configpath, opts):
    """Write env vars and a command prefix into the game's system: block.

    Only the keys Akari manages are touched; everything else in the file is
    passed through byte for byte, which matters because Lutris keeps
    hand-tuned per-game settings in here.
    """
    path = os.path.join(LUTRIS_CFG, f"{configpath}.yml")
    if not os.path.isfile(path):
        print(f"ERR|Lutris config not found: {path}")
        return 1
    env, prefix = split_opts(opts)
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print(f"ERR|{e}")
        return 1

    out, lines = [], text.splitlines()
    i, n = 0, len(lines)
    wrote = False
    while i < n:
        raw = lines[i]
        if raw.strip() == "system:" and not raw.startswith((" ", "\t")):
            out.append(raw)
            i += 1
            # copy the block through, dropping the keys we own
            while i < n and (lines[i].startswith((" ", "\t")) or not lines[i].strip()):
                s = lines[i].strip()
                indent = len(lines[i]) - len(lines[i].lstrip())
                if s == "env:":
                    i += 1   # skip the whole env mapping
                    while i < n and (len(lines[i]) - len(lines[i].lstrip())) > indent \
                            and lines[i].strip():
                        i += 1
                    continue
                if s.startswith("command_prefix:"):
                    i += 1
                    continue
                out.append(lines[i])
                i += 1
            out.extend(render_block())
            wrote = True
            continue
        out.append(raw)
        i += 1
    if not wrote:
        out.append("system:")
        out.extend(render_block())

    tmp = path + ".akari.tmp"
    bak = path + ".akari.bak"
    if not os.path.exists(bak):
        try:
            with open(bak, "w", encoding="utf-8") as f:
                f.write(text)
        except OSError:
            pass
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(out).rstrip() + "\n")
    os.replace(tmp, path)
    print(f"OK|{configpath}")
    return 0

def split_opts(opts):
    """Split an Akari launch string into (env dict, wrapper prefix).

    Leading KEY=VALUE tokens are environment; whatever sits between them
    and %command% is the wrapper chain (gamemoderun, mangohud, gamescope).
    """
    # Env-var names are conventionally SHOUTY, and the ones that matter for
    # a hybrid-GPU laptop start with underscores (__NV_PRIME_RENDER_OFFLOAD),
    # so a plain isupper() check is not enough.
    env, rest = {}, []
    for tok in (opts or "").split():
        if tok == "%command%":
            continue
        if not rest and re.match(r"^[A-Z_][A-Z0-9_]*=", tok):
            k, v = tok.split("=", 1)
            env[k] = v
        else:
            rest.append(tok)
    return env, " ".join(rest)

def render_block():
    env, prefix = split_opts(CURRENT_OPTS[0])
    block = []
    if env:
        block.append("  env:")
        for k, v in env.items():
            block.append(f"    {k}: '{v}'")
    if prefix:
        block.append(f"  command_prefix: '{prefix}'")
    return block

# ---------------------------------------------------------------- heroic
HEROIC = os.path.join(home, ".config/heroic")
HEROIC_STORES = {
    "legendary_library.json": "Epic",
    "gog_library.json": "GOG",
    "nile_library.json": "Amazon",
}

def heroic_game_opts(app_name):
    path = os.path.join(HEROIC, "GamesConfig", f"{app_name}.json")
    if not os.path.isfile(path):
        return ""
    try:
        cfg = json.load(open(path, encoding="utf-8")).get(app_name, {})
    except (OSError, ValueError):
        return ""
    parts = []
    # Upstream really does spell it "enviroment" — matching the file, not
    # the dictionary, is the whole point here.
    for e in cfg.get("enviromentOptions") or []:
        if e.get("key"):
            parts.append(f"{e['key']}={e.get('value', '')}")
    for w in cfg.get("wrapperOptions") or []:
        exe = w.get("exe") or ""
        args = w.get("args") or ""
        if exe:
            parts.append(f"{exe} {args}".strip())
    return " ".join(parts + ["%command%"]) if parts else ""

def heroic_game_runner(app_name):
    path = os.path.join(HEROIC, "GamesConfig", f"{app_name}.json")
    if os.path.isfile(path):
        try:
            cfg = json.load(open(path, encoding="utf-8")).get(app_name, {})
        except (OSError, ValueError):
            cfg = {}
        b = (cfg.get("wineVersion") or {}).get("bin") or ""
        for want in ("tools/proton/", "tools/wine/"):
            if want in b:
                return b.split(want)[1].split("/")[0]
    return default_get("heroic-proton") or default_get("heroic-wine")


def heroic_list():
    if not os.path.isdir(HEROIC):
        return
    cache = os.path.join(HEROIC, "store_cache")
    found = False
    for fname, store in HEROIC_STORES.items():
        path = os.path.join(cache, fname)
        if not os.path.isfile(path):
            continue
        try:
            data = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for g in data.get("library") or []:
            if not g.get("is_installed"):
                continue
            found = True
            app = g.get("app_name") or ""
            inst = g.get("install") or {}
            emit("heroic", app, g.get("title") or app, "installed",
                 human(inst.get("install_size") or 0),
                 heroic_game_runner(app) or inst.get("platform") or store,
                 heroic_game_opts(app))
    if not found:
        unavailable("heroic", "Heroic is set up but no installed games were found in its cache.")

def heroic_set(app_name, opts):
    d = os.path.join(HEROIC, "GamesConfig")
    if not os.path.isdir(d):
        print(f"ERR|Heroic config directory not found: {d}")
        return 1
    path = os.path.join(d, f"{app_name}.json")
    cfg, whole = {}, {}
    original = None
    if os.path.isfile(path):
        try:
            original = open(path, encoding="utf-8").read()
            whole = json.loads(original)
            cfg = whole.get(app_name, {})
        except (OSError, ValueError):
            whole, cfg = {}, {}
    env, prefix = split_opts(opts)
    cfg["enviromentOptions"] = [{"key": k, "value": v} for k, v in env.items()]
    if prefix:
        toks = prefix.split()
        cfg["wrapperOptions"] = [{"exe": toks[0], "args": " ".join(toks[1:])}]
    else:
        cfg["wrapperOptions"] = []
    whole[app_name] = cfg
    if original is not None:
        bak = path + ".akari.bak"
        if not os.path.exists(bak):
            try:
                with open(bak, "w", encoding="utf-8") as f:
                    f.write(original)
            except OSError:
                pass
    tmp = path + ".akari.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(whole, f, indent=2)
    os.replace(tmp, path)
    print(f"OK|{app_name}")
    return 0

# ---------------------------------------------------------------- runners
# Which build a game runs on. Installing a build never selects it, so this
# is what actually makes a freshly downloaded GE-Proton take effect.

def runner_paths(target, build):
    """(directory, executable, heroic type) for a build under a target."""
    if target == "lutris":
        d = os.path.join(home, ".local/share/lutris/runners/wine", build)
        return d, os.path.join(d, "bin/wine"), "wine"
    if target == "heroic-proton":
        d = os.path.join(HEROIC, "tools/proton", build)
        return d, os.path.join(d, "proton"), "proton"
    if target == "heroic-wine":
        d = os.path.join(HEROIC, "tools/wine", build)
        return d, os.path.join(d, "bin/wine"), "wine"
    return None, None, None


def heroic_wine_version(target, build):
    _d, binary, kind = runner_paths(target, build)
    label = "Proton" if kind == "proton" else "Wine"
    return {"bin": binary, "name": f"{label} - {build}", "type": kind}


def lutris_default_path():
    return os.path.join(home, ".config/lutris/runners/wine.yml")


def default_get(target):
    if target == "lutris":
        path = lutris_default_path()
        if not os.path.isfile(path):
            return ""
        for raw in open(path, encoding="utf-8", errors="replace"):
            s2 = raw.strip()
            if s2.startswith("version:"):
                return s2.split(":", 1)[1].strip().strip("'").strip('"')
        return ""
    if target.startswith("heroic"):
        path = os.path.join(HEROIC, "config.json")
        if not os.path.isfile(path):
            return ""
        try:
            cfg = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError):
            return ""
        wv = (cfg.get("defaultSettings") or {}).get("wineVersion") or {}
        # Report the build directory name, not Heroic's display label, so it
        # can be compared against what the Proton page lists.
        b = wv.get("bin") or ""
        if not b:
            return ""
        want = "tools/proton" if target == "heroic-proton" else "tools/wine"
        if want not in b:
            return ""
        parts = b.split(want + "/")
        return parts[1].split("/")[0] if len(parts) > 1 else ""
    return ""


def backup_once(path, text):
    bak = path + ".akari.bak"
    if not os.path.exists(bak):
        try:
            with open(bak, "w", encoding="utf-8") as f:
                f.write(text)
        except OSError:
            pass


def default_set(target, build):
    d, binary, _kind = runner_paths(target, build)
    if d is None:
        print(f"ERR|unknown target {target}")
        return 1
    if not os.path.isdir(d):
        print(f"ERR|{build} is not installed at {d}")
        return 1

    if target == "lutris":
        path = lutris_default_path()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        original = ""
        if os.path.isfile(path):
            original = open(path, encoding="utf-8", errors="replace").read()
            backup_once(path, original)
        out, seen_wine, wrote = [], False, False
        for raw in original.splitlines():
            st = raw.strip()
            if st == "wine:":
                seen_wine = True
                out.append(raw)
                continue
            if seen_wine and st.startswith("version:"):
                out.append(f"  version: {build}")
                wrote = True
                continue
            out.append(raw)
        if not seen_wine:
            out.append("wine:")
            out.append(f"  version: {build}")
        elif not wrote:
            idx = out.index("wine:")
            out.insert(idx + 1, f"  version: {build}")
        tmp = path + ".akari.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(out).rstrip() + "\n")
        os.replace(tmp, path)
        print(f"OK|{build}")
        return 0

    path = os.path.join(HEROIC, "config.json")
    if not os.path.isfile(path):
        print(f"ERR|Heroic config not found: {path}")
        return 1
    original = open(path, encoding="utf-8").read()
    try:
        cfg = json.loads(original)
    except ValueError:
        print("ERR|Heroic config.json is not valid JSON")
        return 1
    backup_once(path, original)
    cfg.setdefault("defaultSettings", {})["wineVersion"] = \
        heroic_wine_version(target, build)
    tmp = path + ".akari.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    os.replace(tmp, path)
    print(f"OK|{build}")
    return 0


def runner_set(source, gid, target, build):
    """Pin one game to a build, leaving every other game alone."""
    d, binary, _kind = runner_paths(target, build)
    if d is None or not os.path.isdir(d):
        print(f"ERR|{build} is not installed for {target}")
        return 1

    if source == "lutris":
        path = os.path.join(LUTRIS_CFG, f"{gid}.yml")
        if not os.path.isfile(path):
            print(f"ERR|Lutris config not found: {path}")
            return 1
        original = open(path, encoding="utf-8", errors="replace").read()
        backup_once(path, original)
        out, seen, wrote = [], False, False
        for raw in original.splitlines():
            st = raw.strip()
            if not raw.startswith((" ", "\t")) and st.endswith(":"):
                seen = (st == "wine:")
            if seen and st.startswith("version:"):
                out.append(f"  version: {build}")
                wrote = True
                continue
            out.append(raw)
        if not wrote:
            out.append("wine:")
            out.append(f"  version: {build}")
        tmp = path + ".akari.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(out).rstrip() + "\n")
        os.replace(tmp, path)
        print(f"OK|{build}")
        return 0

    if source == "heroic":
        cfgdir = os.path.join(HEROIC, "GamesConfig")
        os.makedirs(cfgdir, exist_ok=True)
        path = os.path.join(cfgdir, f"{gid}.json")
        whole, original = {}, None
        if os.path.isfile(path):
            original = open(path, encoding="utf-8").read()
            try:
                whole = json.loads(original)
            except ValueError:
                whole = {}
            backup_once(path, original)
        entry = whole.get(gid, {})
        entry["wineVersion"] = heroic_wine_version(target, build)
        whole[gid] = entry
        tmp = path + ".akari.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(whole, f, indent=2)
        os.replace(tmp, path)
        print(f"OK|{build}")
        return 0

    print(f"ERR|unknown source {source}")
    return 1


# ---------------------------------------------------------------- dispatch
CURRENT_OPTS = [""]

if cmd == "list":
    lutris_list()
    heroic_list()
elif cmd == "set-lutris":
    CURRENT_OPTS[0] = sys.argv[4]
    sys.exit(lutris_set(sys.argv[3], sys.argv[4]))
elif cmd == "set-heroic":
    CURRENT_OPTS[0] = sys.argv[4]
    sys.exit(heroic_set(sys.argv[3], sys.argv[4]))
elif cmd == "default-get":
    print(default_get(sys.argv[3]))
elif cmd == "default-set":
    sys.exit(default_set(sys.argv[3], sys.argv[4]))
elif cmd == "set-runner":
    sys.exit(runner_set(sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]))
else:
    sys.exit(f"unknown command {cmd}")
PYEOF
}

# ---- listing -----------------------------------------------------------

cmd_games() {
  games_steam
  games_py list 2>/dev/null || true
  return 0
}

# Resolve a game's display name for plan/log text, without a second scan
# of every launcher.
game_name_of() {   # game_name_of <source> <id>
  local src="$1" id="$2"
  cmd_games 2>/dev/null | awk -F'|' -v s="$src" -v i="$id" \
    '$1=="GAM" && $2==s && $3==i {print $4; exit}' \
    | while IFS= read -r n; do gam_dec "$n"; done
}

# ---- launch options write-back -----------------------------------------

plan_gameopts() {   # plan_gameopts <source> <id> <options>
  local src="${1:-}" id="${2:-}" opts="${3:-}"
  echo "== Plan: set launch options =="
  local name; name=$(game_name_of "$src" "$id")
  echo "Game:    ${name:-$id}"
  echo "Source:  $src"
  echo "Options: ${opts:-<clear>}"
  case "$src" in
    steam)
      local cfg; cfg=$(steam_localconfig)
      echo "File:    ${cfg:-<not found>} (backed up first)"
      if steam_running; then
        echo ""
        echo "! Steam is RUNNING. It keeps this file in memory and rewrites it on"
        echo "  exit, so the change would vanish. Close Steam first — apply refuses"
        echo "  while it is running."
      fi ;;
    lutris)
      echo "File:    $RUN_HOME/.config/lutris/games/$id.yml (backed up first)"
      echo ""
      echo "Environment variables go into 'system: env:', wrappers into"
      echo "'command_prefix'. Your other per-game settings are left alone."
      if launcher_running lutris; then
        echo ""
        echo "! Lutris is RUNNING and caches game configs — close it first. Apply"
        echo "  refuses while it is running."
      fi ;;
    heroic)
      echo "File:    $RUN_HOME/.config/heroic/GamesConfig/$id.json (backed up first)"
      echo ""
      echo "Environment variables go into 'enviromentOptions', wrappers into"
      echo "'wrapperOptions'."
      if launcher_running heroic; then
        echo ""
        echo "! Heroic is RUNNING and rewrites its config on exit — close it first."
        echo "  Apply refuses while it is running."
      fi ;;
    *) echo "Unknown source '$src'." ;;
  esac
}

apply_gameopts() {   # apply_gameopts <source> <id> <options>
  local src="${1:-}" id="${2:-}" opts="${3:-}"
  [[ -n "$src" && -n "$id" ]] || { echo ":: usage: apply gameopts <source> <id> \"<options>\""; return 1; }

  case "$src" in
    steam)
      # Steam already has a dedicated, tested path — reuse it rather than
      # growing a second VDF writer.
      apply_launchopts "$id" "$opts" ;;
    lutris)
      [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || { echo ":: invalid Lutris config id."; return 1; }
      if launcher_running lutris; then
        echo ":: Lutris is running — it may overwrite this from its cache."
        echo ":: Close Lutris and try again."
        return 1
      fi
      local out
      if ! out=$(games_py set-lutris "$id" "$opts"); then
        echo ":: Edit failed: ${out#ERR|}"
        return 1
      fi
      [[ $out == ERR\|* ]] && { echo ":: ${out#ERR|}"; return 1; }
      log_change "set Lutris launch options for $id: ${opts:-<cleared>}"
      echo ":: Launch options for '$(game_name_of lutris "$id")' set to: ${opts:-<cleared>}" ;;
    heroic)
      if launcher_running heroic; then
        echo ":: Heroic is running — it rewrites its config on exit."
        echo ":: Close Heroic and try again."
        return 1
      fi
      local hout
      if ! hout=$(games_py set-heroic "$id" "$opts"); then
        echo ":: Edit failed: ${hout#ERR|}"
        return 1
      fi
      [[ $hout == ERR\|* ]] && { echo ":: ${hout#ERR|}"; return 1; }
      log_change "set Heroic launch options for $id: ${opts:-<cleared>}"
      echo ":: Launch options for '$(game_name_of heroic "$id")' set to: ${opts:-<cleared>}" ;;
    *)
      echo ":: unknown source '$src' (expected steam, lutris or heroic)."
      return 1 ;;
  esac
}

# ---- per-game compatibility tool ---------------------------------------
# Separate from launch options on purpose: launch options wrap the command,
# this decides which Proton/Wine actually runs it. Installing a build does
# neither, which is why a new GE-Proton appears to do nothing until one of
# these is set.

# Which install target holds this build for a given launcher. Heroic keeps
# Proton and Wine builds in different directories, so the answer decides
# what gets written into its config.
# Returns non-zero when the build is not actually installed for that
# launcher — otherwise a typo would be written into the config and the game
# would fall back to stock Proton with no explanation.
runner_target_for() {   # runner_target_for <source> <build>
  local src="$1" build="$2" t dir
  local -a candidates=()
  case "$src" in
    steam)  candidates=(steam) ;;
    lutris) candidates=(lutris) ;;
    heroic) candidates=(heroic-proton heroic-wine) ;;
    *) return 1 ;;
  esac
  for t in "${candidates[@]}"; do
    dir=$(proton_target_dir "$t") || continue
    [[ -d "$dir/$build" ]] && { echo "$t"; return 0; }
  done
  return 1
}

# Builds this game could be switched to, one per line.
runner_choices() {   # runner_choices <source>
  local src="$1" t dir n
  case "$src" in
    steam)  t=steam ;;
    lutris) t=lutris ;;
    heroic)
      for t in heroic-proton heroic-wine; do
        dir=$(proton_target_dir "$t") || continue
        proton_installed_in "$dir"
      done
      return 0 ;;
    *) return 0 ;;
  esac
  dir=$(proton_target_dir "$t") || return 0
  proton_installed_in "$dir"
  return 0
}

plan_gamerunner() {   # plan_gamerunner <source> <id> <build>
  local src="${1:-}" gid="${2:-}" build="${3:-}"
  echo "== Plan: change compatibility tool =="
  local name; name=$(game_name_of "$src" "$gid")
  echo "Game:  ${name:-$gid}"
  echo "Use:   $build"
  local target; target=$(runner_target_for "$src" "$build") || {
    echo ""
    echo "$build is not installed for $src — install it on the Proton page first."
    return 0; }
  case "$src" in
    steam)
      echo "File:  $(steam_configvdf) (backed up first)"
      echo ""
      echo "Same as Properties > Compatibility > 'Force the use of a specific"
      echo "Steam Play compatibility tool'. This overrides the global default"
      echo "for this game only."
      launcher_running steam && {
        echo ""
        echo "! Steam is RUNNING and rewrites config.vdf on exit — close it first."
        echo "  Apply refuses while it is running."; } ;;
    lutris)
      echo "File:  $RUN_HOME/.config/lutris/games/$gid.yml (backed up first)"
      launcher_running lutris && {
        echo ""
        echo "! Lutris is RUNNING and caches game configs — close it first."; } ;;
    heroic)
      echo "File:  $RUN_HOME/.config/heroic/GamesConfig/$gid.json (backed up first)"
      echo "Type:  ${target#heroic-}"
      launcher_running heroic && {
        echo ""
        echo "! Heroic is RUNNING and rewrites its config on exit — close it first."; } ;;
  esac
  echo ""
  echo "Takes effect the next time the game is launched. Existing Proton"
  echo "prefixes are left alone; a big version jump can still make a game"
  echo "want a fresh prefix."
}

apply_gamerunner() {   # apply_gamerunner <source> <id> <build>
  local src="${1:-}" gid="${2:-}" build="${3:-}"
  [[ -n "$src" && -n "$gid" && -n "$build" ]] || {
    echo ":: usage: apply gamerunner <source> <id> <build>"; return 1; }
  [[ "$build" =~ ^[A-Za-z0-9._-]+$ ]] || { echo ":: invalid build name."; return 1; }

  local target; target=$(runner_target_for "$src" "$build") || {
    echo ":: $build is not installed for $src — install it on the Proton page first."
    return 1; }

  if launcher_running "$src"; then
    echo ":: $src is running and would overwrite this on exit."
    echo ":: Close it and try again."
    return 1
  fi

  local out
  case "$src" in
    steam)
      [[ "$gid" =~ ^[0-9]+$ ]] || { echo ":: invalid appid."; return 1; }
      local cfg; cfg=$(steam_configvdf)
      [[ -n "$cfg" ]] || { echo ":: Steam's config.vdf not found — start Steam once first."; return 1; }
      local bak="${cfg}.akari.bak"
      run_user cp "$cfg" "$bak"
      echo ":: Backup: $bak"
      if ! out=$(vdf_py compat-set "$cfg" "$gid" "$build"); then
        echo ":: Edit failed — restoring backup."
        run_user cp "$bak" "$cfg"
        return 1
      fi ;;
    lutris|heroic)
      [[ "$gid" =~ ^[A-Za-z0-9._-]+$ ]] || { echo ":: invalid game id."; return 1; }
      if ! out=$(games_py set-runner "$src" "$gid" "$target" "$build"); then
        echo ":: Edit failed: ${out#ERR|}"
        return 1
      fi
      [[ $out == ERR\|* ]] && { echo ":: ${out#ERR|}"; return 1; } ;;
    *) echo ":: unknown source '$src'."; return 1 ;;
  esac

  log_change "set compatibility tool for $src game $gid to $build"
  echo ":: '$(game_name_of "$src" "$gid")' will now run on $build."
  echo ":: Restart the launcher, then launch the game."
}
