#!/usr/bin/env bash
# Akari Tool backend module — sourced by akari-setup.sh; not standalone.

# ---- steam per-game launch options ------------------------------------
# Reads/writes LaunchOptions in Steam's localconfig.vdf so the Launch
# Options page can apply its built string directly to a game.
# VDF is a fussy quasi-format (escaped quotes, case-varying keys), so the
# actual parsing lives in an embedded python3 helper — python is already a
# hard dependency of the GUI. All orchestration and safety stays in bash.

steam_localconfig() {   # newest localconfig.vdf across Steam users, or ""
  local base
  for base in "$RUN_HOME/.local/share/Steam" "$RUN_HOME/.steam/steam"; do
    [[ -d "$base/userdata" ]] || continue
    find "$base/userdata" -maxdepth 3 -name localconfig.vdf \
      -printf '%T@ %p\n' 2>/dev/null
  done | sort -rn | head -1 | cut -d' ' -f2-
}

steam_running() { pgrep -x steam &>/dev/null || pgrep -f 'steamwebhelper' &>/dev/null; }

# vdf_py <list|set> <localconfig> <steamapps-dir> [appid] [options]
vdf_py() {
  run_user python3 - "$@" <<'PYEOF'
import re, sys, os, glob

def tokenize(text):
    i, n, out = 0, len(text), []
    while i < n:
        c = text[i]
        if c in ' \t\r\n': i += 1
        elif text.startswith('//', i): i = text.find('\n', i) % (n + 1)
        elif c in '{}': out.append(c); i += 1
        elif c == '"':
            j, buf = i + 1, []
            while j < n:
                if text[j] == '\\' and j + 1 < n:
                    buf.append({'n':'\n','t':'\t','\\':'\\','"':'"'}.get(text[j+1], text[j+1])); j += 2
                elif text[j] == '"': break
                else: buf.append(text[j]); j += 1
            out.append(('s', ''.join(buf))); i = j + 1
        else:  # bare token (rare in localconfig)
            j = i
            while j < n and text[j] not in ' \t\r\n{}': j += 1
            out.append(('s', text[i:j])); i = j
    return out

def parse(tokens):
    def block(pos):
        d = {}
        while pos < len(tokens):
            t = tokens[pos]
            if t == '}': return d, pos + 1
            key = t[1]; pos += 1
            if tokens[pos] == '{':
                val, pos = block(pos + 1)
            else:
                val = tokens[pos][1]; pos += 1
            d[key] = val
        return d, pos
    key = tokens[0][1]
    val, _ = block(2)  # skip name + '{'
    return key, val

def esc(s): return s.replace('\\', '\\\\').replace('"', '\\"')

def dump(key, d, ind=0):
    pad = '\t' * ind
    out = [f'{pad}"{esc(key)}"', pad + '{']
    for k, v in d.items():
        if isinstance(v, dict):
            out.append(dump(k, v, ind + 1))
        else:
            tabs = '\t' * (ind + 1)
            out.append(f'{tabs}"{esc(k)}"\t\t"{esc(v)}"')
    out.append(pad + '}')
    return '\n'.join(out)

def get_ci(d, key):
    for k in d:
        if k.lower() == key.lower(): return d[k]
    return None

cmd, path = sys.argv[1], sys.argv[2]
text = open(path, encoding='utf-8', errors='replace').read()
root_key, root = parse(tokenize(text))


def section(*parts):
    """Walk down a VDF tree case-insensitively, creating missing levels.

    Steam varies the capitalisation of these keys between client versions,
    and CompatToolMapping simply does not exist until the user picks a
    compatibility tool for the first time.
    """
    node = root
    for part in parts:
        nxt = get_ci(node, part)
        if nxt is None:
            nxt = {}
            node[part] = nxt
        node = nxt
    return node


# localconfig.vdf holds per-game launch options; config.vdf holds the
# compatibility-tool mapping. Same format, different trees.
if cmd in ('list', 'set'):
    apps = section('Software', 'Valve', 'Steam', 'apps')
    steamapps = sys.argv[3]
    names = {}
    for m in glob.glob(os.path.join(steamapps, 'appmanifest_*.acf')):
        try: acf = open(m, encoding='utf-8', errors='replace').read()
        except OSError: continue
        a = re.search(r'"appid"\s+"(\d+)"', acf)
        nm = re.search(r'"name"\s+"((?:[^"\\]|\\.)*)"', acf)
        if a and nm: names[a.group(1)] = nm.group(1).replace('\\"', '"')

if cmd == 'list':
    for appid, entry in apps.items():
        if not appid.isdigit() or appid not in names: continue
        lo = get_ci(entry, 'LaunchOptions') if isinstance(entry, dict) else None
        print(f'SGM|{appid}|{names[appid]}|{(lo or "").replace("|", " ")}')
elif cmd == 'set':
    appid, opts = sys.argv[4], sys.argv[5]
    entry = apps.get(appid)
    if entry is None:
        apps[appid] = entry = {}
    for k in list(entry):
        if k.lower() == 'launchoptions': del entry[k]
    if opts: entry['LaunchOptions'] = opts
    tmp = path + '.akari.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(dump(root_key, root) + '\n')
    os.replace(tmp, path)
    print(f'OK|{names.get(appid, appid)}')
elif cmd == 'compat-get':
    # appid "0" is Steam's own key for "Enable Steam Play for all other
    # titles" — the global default. Everything else is a per-game override.
    mapping = section('Software', 'Valve', 'Steam', 'CompatToolMapping')
    for appid, entry in mapping.items():
        if not isinstance(entry, dict):
            continue
        tool = get_ci(entry, 'name') or ''
        if tool:
            print(f'CMP|{appid}|{tool}')
elif cmd == 'compat-set':
    appid, tool = sys.argv[3], sys.argv[4]
    mapping = section('Software', 'Valve', 'Steam', 'CompatToolMapping')
    entry = get_ci(mapping, appid)
    if not isinstance(entry, dict):
        entry = {}
        mapping[appid] = entry
    if tool:
        # Preserve the existing key casing so a diff against Steam's own
        # output stays quiet.
        for k in list(entry):
            if k.lower() in ('name', 'config', 'priority'):
                del entry[k]
        entry['name'] = tool
        entry['config'] = ''
        # Steam writes 75 for the global default and 250 for a per-game
        # override; matching those keeps its own precedence rules intact.
        entry['priority'] = '75' if appid == '0' else '250'
    else:
        mapping.pop(appid, None)
    tmp = path + '.akari.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(dump(root_key, root) + '\n')
    os.replace(tmp, path)
    print(f'OK|{tool or "<cleared>"}')
PYEOF
}

steam_steamapps() {   # steamapps dir matching the localconfig's install
  local base
  for base in "$RUN_HOME/.local/share/Steam" "$RUN_HOME/.steam/steam"; do
    [[ -d "$base/steamapps" ]] && { echo "$base/steamapps"; return; }
  done
}

cmd_steam_games() {
  local cfg; cfg=$(steam_localconfig)
  [[ -n "$cfg" ]] || { echo 'ERR|no-steam|Steam user data not found'; return 0; }
  vdf_py list "$cfg" "$(steam_steamapps)" 2>/dev/null | sort -t'|' -k3 || true
}

plan_launchopts() {   # plan_launchopts <appid> <options>
  local appid="${1:-}" opts="${2:-}"
  echo "== Plan: set Steam launch options =="
  local cfg; cfg=$(steam_localconfig)
  [[ -n "$cfg" ]] || { echo "Steam user data not found — is Steam installed and logged in?"; return 0; }
  local name
  name=$(cmd_steam_games | awk -F'|' -v id="$appid" '$2==id {print $3}')
  echo "Game:    ${name:-appid $appid}"
  echo "Options: ${opts:-<clear>}"
  echo "File:    $cfg (backed up first)"
  if steam_running; then
    echo ""
    echo "! Steam is RUNNING. It rewrites this file on exit and would overwrite"
    echo "  the change — close Steam first. Apply will refuse while it runs."
  fi
}

apply_launchopts() {   # apply_launchopts <appid> <options>
  local appid="${1:-}" opts="${2:-}"
  [[ "$appid" =~ ^[0-9]+$ ]] || { echo ":: invalid appid"; return 1; }
  local cfg; cfg=$(steam_localconfig)
  [[ -n "$cfg" ]] || { echo ":: Steam user data not found."; return 1; }
  if steam_running; then
    echo ":: Steam is running — it would overwrite this change on exit."
    echo ":: Close Steam and try again."
    return 1
  fi
  local bak="${cfg}.akari.bak"
  run_user cp "$cfg" "$bak"
  echo ":: Backup: $bak"
  local out
  if ! out=$(vdf_py set "$cfg" "$(steam_steamapps)" "$appid" "$opts"); then
    echo ":: Edit failed — restoring backup."
    run_user cp "$bak" "$cfg"
    return 1
  fi
  local name="${out#OK|}"
  log_change "set Steam launch options for $name (appid $appid): ${opts:-<cleared>} (backup: $bak)"
  echo ":: Launch options for '$name' set to: ${opts:-<cleared>}"
  echo ":: They take effect the next time Steam starts."
}

