#!/usr/bin/env bash
#
# tui/lib/ui.sh — shared terminal UI primitives for the Akari frontends.
#
# Sourced by tui/akari-tui and tui/akari-install. Pure bash + coreutils,
# so it also works on a bare Arch ISO. Contains no Akari logic whatsoever:
# only drawing, input and generic screens.
#
# ---------------------------------------------------------------- theme

if [[ -t 1 ]] && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
  C_RST=$'\e[0m';  C_DIM=$'\e[2m';  C_B=$'\e[1m'
  C_RED=$'\e[38;5;203m'        # Akari red
  C_REDB=$'\e[48;5;203m'$'\e[38;5;232m'
  C_GRN=$'\e[38;5;114m'; C_YEL=$'\e[38;5;179m'; C_ERR=$'\e[38;5;167m'
  C_MUT=$'\e[38;5;245m'; C_SEP=$'\e[38;5;238m'
else
  C_RST=''; C_DIM=''; C_B=''; C_RED=''; C_REDB=$'\e[7m'
  C_GRN=''; C_YEL=''; C_ERR=''; C_MUT=''; C_SEP=''
fi

# state token -> coloured glyph
dot() {
  case "$1" in
    ok)   printf '%s' "${C_GRN}●${C_RST}" ;;
    warn) printf '%s' "${C_YEL}●${C_RST}" ;;
    fail) printf '%s' "${C_ERR}●${C_RST}" ;;
    on)   printf '%s' "${C_GRN}✓${C_RST}" ;;
    off)  printf '%s' "${C_SEP}·${C_RST}" ;;
    *)    printf '%s' " " ;;
  esac
}

dot_plain() {
  case "$1" in
    ok|warn|fail) printf '●' ;;
    on)  printf '✓' ;;
    off) printf '·' ;;
    *)   printf ' ' ;;
  esac
}

# ---------------------------------------------------------------- terminal

TERM_READY=0
term_init() {
  [[ -t 0 && -t 1 ]] || return 0
  printf '\e[?1049h\e[?25l'
  stty -echo 2>/dev/null
  TERM_READY=1
}
term_done() {
  (( TERM_READY )) || return 0
  printf '\e[?25h\e[?1049l'
  stty echo 2>/dev/null
  TERM_READY=0
}
trap 'term_done; exit 130' INT
trap 'term_done' EXIT

H=24; W=80
term_size() {
  H=$(tput lines 2>/dev/null || echo 24)
  W=$(tput cols  2>/dev/null || echo 80)
  (( H < 12 )) && H=12
  (( W < 50 )) && W=50
}

# ---------------------------------------------------------------- frame buffer
# Lines are built as PLAIN text, padded to a known width, and only then
# wrapped in colour. That keeps every width calculation honest.

FB=()
fb_reset() { FB=(); }
fb() { FB+=("$1"); }
fb_flush() {
  local i=1 l
  for l in "${FB[@]}"; do
    printf '\e[%d;1H%s\e[K' "$i" "$l"
    (( i++ ))
  done
  printf '\e[J'
}

# truncate plain text to N columns, with an ellipsis if it had to cut
trunc() {
  local s=$1 n=$2
  (( ${#s} <= n )) && { printf '%s' "$s"; return; }
  (( n <= 1 )) && { printf '%s' "${s:0:n}"; return; }
  printf '%s…' "${s:0:$((n-1))}"
}

pad() { printf '%-*s' "$2" "$(trunc "$1" "$2")"; }

wrap() {   # wrap $1 to width $2, echo one line per row
  local text=$1 width=$2
  [[ -z $text ]] && return 0
  printf '%s\n' "$text" | fold -s -w "$width" | sed 's/[[:space:]]*$//'
}

# ---------------------------------------------------------------- chrome

BREADCRUMB="Home"

draw_header() {
  local title=$1
  local bar; bar=$(printf '%*s' "$W" ''); bar=${bar// /─}
  fb "${C_RED}${C_B}  A K A R I${C_RST}${C_MUT}  tool for arch · tui${C_RST}"
  fb "${C_SEP}${bar}${C_RST}"
  fb "  ${C_B}$(pad "$title" $((W-4)))${C_RST}"
  fb ""
}

draw_footer() {
  local keys=$1
  local bar; bar=$(printf '%*s' "$W" ''); bar=${bar// /─}
  fb "${C_SEP}${bar}${C_RST}"
  fb "${C_MUT}  $(pad "$keys" $((W-4)))${C_RST}"
}

# ---------------------------------------------------------------- input

key() {
  local k rest
  IFS= read -rsn1 k 2>/dev/null || { echo quit; return; }
  case $k in
    '')  echo enter; return ;;
    ' ') echo space; return ;;
    $'\t') echo tab; return ;;
    $'\177'|$'\b') echo back; return ;;
  esac
  if [[ $k == $'\e' ]]; then
    read -rsn2 -t 0.05 rest 2>/dev/null
    case $rest in
      '[A') echo up ;;   '[B') echo down ;;
      '[C') echo right ;; '[D') echo left ;;
      '[H') echo home ;;  '[F') echo end ;;
      '[5') read -rsn1 -t 0.05 2>/dev/null; echo pgup ;;
      '[6') read -rsn1 -t 0.05 2>/dev/null; echo pgdn ;;
      '')   echo esc ;;
      *)    echo other ;;
    esac
    return
  fi
  printf '%s\n' "$k"
}

# ---------------------------------------------------------------- list screen
# Inputs (globals):  L_LABEL[]  L_DESC[]  L_STATE[]  L_TAG[]  L_SEL[]
# L_STATE / L_TAG / L_SEL are optional. L_SEL turns the screen into a
# multi-select (space toggles, enter confirms the whole set).
# Outputs: L_INDEX, and the return code:
#   0 = enter/confirm   1 = back   2 = quit

L_LABEL=(); L_DESC=(); L_STATE=(); L_TAG=(); L_SEL=()
L_INDEX=0

list_screen() {
  local title=$1 keys=${2:-} multi=${3:-0}
  local n=${#L_LABEL[@]}
  (( n == 0 )) && return 1
  local cur=0 top=0 lw rows i k

  while :; do
    term_size
    rows=$(( H - 6 ))
    (( rows < 3 )) && rows=3
    lw=$(( W * 46 / 100 ))
    (( lw < 26 )) && lw=26
    (( lw > 52 )) && lw=52
    (( lw > W - 20 )) && lw=$(( W - 20 ))

    (( cur < top )) && top=$cur
    (( cur >= top + rows )) && top=$(( cur - rows + 1 ))
    (( top < 0 )) && top=0

    # right-hand description pane, pre-wrapped for the current item
    local -a dlines=()
    local dw=$(( W - lw - 5 ))
    (( dw < 10 )) && dw=10
    while IFS= read -r l; do dlines+=("$l"); done < <(wrap "${L_DESC[cur]:-}" "$dw")

    fb_reset
    draw_header "$title"

    for (( i = 0; i < rows; i++ )); do
      local idx=$(( top + i )) left="" right=""
      if (( idx < n )); then
        local st="${L_STATE[idx]:-}" tag="${L_TAG[idx]:-}" mark=""
        if (( multi )); then
          mark=$([[ ${L_SEL[idx]:-0} == 1 ]] && echo "[x] " || echo "[ ] ")
        fi
        # content column: everything after the 2-column status prefix
        local cw=$(( lw - 2 )); (( cw < 8 )) && cw=8
        local body="${mark}${L_LABEL[idx]}" content
        if [[ -n $tag ]]; then
          local tw=$(( ${#tag} + 3 ))
          (( tw > cw - 6 )) && tw=$(( cw - 6 ))
          content="$(pad "$body" $(( cw - tw )))$(printf '%*s ' $(( tw - 1 )) "$(trunc "$tag" $(( tw - 1 )))")"
        else
          content="$(pad "$body" "$cw")"
        fi
        # The glyph is never measured — it is emitted verbatim, one column.
        if (( idx == cur )); then
          left="${C_REDB}$(dot_plain "$st") ${content}${C_RST}"
        else
          left="$(dot "$st") ${content}"
        fi
      else
        left="$(printf '%*s' "$lw" '')"
      fi
      (( i < ${#dlines[@]} )) && right="${dlines[i]}"
      fb "${left}${C_SEP}│${C_RST} ${right}"
    done

    local pos=""
    (( n > rows )) && pos="  ($((cur+1))/$n)"
    draw_footer "${keys}${pos}"
    fb_flush

    k=$(key)
    case $k in
      up|k)     (( cur > 0 )) && (( cur-- )) ;;
      down|j)   (( cur < n-1 )) && (( cur++ )) ;;
      pgup)     cur=$(( cur - rows )); (( cur < 0 )) && cur=0 ;;
      pgdn)     cur=$(( cur + rows )); (( cur > n-1 )) && cur=$(( n-1 )) ;;
      home|g)   cur=0 ;;
      end|G)    cur=$(( n-1 )) ;;
      space)    if (( multi )); then
                  L_SEL[cur]=$([[ ${L_SEL[cur]:-0} == 1 ]] && echo 0 || echo 1)
                fi ;;
      enter)    L_INDEX=$cur; return 0 ;;
      esc|back|left|h) return 1 ;;
      q)        return 2 ;;
      *) ;;
    esac
  done
}

# ---------------------------------------------------------------- pager

pager_screen() {   # pager_screen <title> <line...>
  local title=$1; shift
  local -a lines=("$@")
  local n=${#lines[@]} top=0 rows k i
  (( n == 0 )) && lines=("(nothing to show)") && n=1
  while :; do
    term_size
    rows=$(( H - 6 )); (( rows < 3 )) && rows=3
    (( top > n - rows )) && top=$(( n - rows ))
    (( top < 0 )) && top=0
    fb_reset
    draw_header "$title"
    for (( i = 0; i < rows; i++ )); do
      local idx=$(( top + i ))
      if (( idx < n )); then fb "  ${lines[idx]}"; else fb ""; fi
    done
    draw_footer "${PAGER_KEYS:-↑↓ scroll   esc back   q quit}   ($((top+1))-$((top+rows>n?n:top+rows))/$n)"
    fb_flush
    k=$(key)
    case $k in
      up|k)   (( top > 0 )) && (( top-- )) ;;
      down|j) (( top < n-1 )) && (( top++ )) ;;
      pgup)   top=$(( top - rows )) ;;
      pgdn)   top=$(( top + rows )) ;;
      home|g) top=0 ;;
      end|G)  top=$(( n - rows )) ;;
      enter|right) return 0 ;;
      esc|back|left|h) return 1 ;;
      q) return 2 ;;
    esac
  done
}

# ---------------------------------------------------------------- shell-out
# Applies leave the alternate screen entirely: output scrolls normally and,
# crucially, sudo has a real tty to prompt on.

pause_key() {
  printf '\n%s[ press any key to return ]%s' "$C_MUT" "$C_RST"
  stty -echo 2>/dev/null
  IFS= read -rsn1 2>/dev/null
  stty echo 2>/dev/null
  printf '\n'
}

rule() { local b; b=$(printf '%*s' "${W:-80}" ''); printf '%s%s%s\n' "$C_SEP" "${b// /─}" "$C_RST"; }

# ---------------------------------------------------------------- list state

clear_list() { L_LABEL=(); L_DESC=(); L_STATE=(); L_TAG=(); L_SEL=(); }

# ---------------------------------------------------------------- helpers

msgbox() {   # msgbox <title> <text>
  local title=$1 text=$2
  local -a lines=()
  term_size
  while IFS= read -r l; do lines+=("$l"); done < <(wrap "$text" $(( W - 6 )))
  pager_screen "$title" "" "${lines[@]}" "" "(esc to go back)"
  return 0
}

# A brief "working…" frame, drawn on the alternate screen before a slow
# backend call so the UI never looks frozen.
busy() {
  (( TERM_READY )) || return 0
  term_size
  fb_reset
  draw_header "Working"
  local i
  for (( i = 0; i < H - 6; i++ )); do fb ""; done
  draw_footer "$1"
  fb_flush
}

# ---------------------------------------------------------------- text entry

# input_screen <title> <prompt> <default> <text|password> [help text]
# Sets INPUT_VALUE. Returns 0 on enter, 1 on esc.
INPUT_VALUE=""
input_screen() {
  local title=$1 prompt=$2 buf=${3:-} mode=${4:-text} help=${5:-}
  local k i rows shown
  INPUT_VALUE=""
  while :; do
    term_size
    rows=$(( H - 6 ))
    fb_reset
    draw_header "$title"
    local -a body=("" "  $prompt" "")
    if [[ $mode == password ]]; then
      shown=$(printf '%*s' "${#buf}" ''); shown=${shown// /•}
    else
      shown=$buf
    fi
    body+=("  ${C_RED}▸${C_RST} ${shown}${C_REDB} ${C_RST}")
    body+=("")
    if [[ -n $help ]]; then
      while IFS= read -r l; do body+=("  ${C_MUT}${l}${C_RST}"); done \
        < <(wrap "$help" $(( W - 6 )))
    fi
    for (( i = 0; i < rows; i++ )); do
      if (( i < ${#body[@]} )); then fb "${body[i]}"; else fb ""; fi
    done
    draw_footer "type to edit   enter accept   esc cancel"
    fb_flush

    k=$(key)
    case $k in
      enter) INPUT_VALUE=$buf; return 0 ;;
      esc)   return 1 ;;
      back)  buf=${buf%?} ;;
      space) buf+=" " ;;
      up|down|left|right|pgup|pgdn|home|end|tab|other|quit) : ;;
      *)     [[ ${#k} -eq 1 ]] && buf+="$k" ;;
    esac
  done
}

# confirm_typed <title> <text> <word>
# The user must type <word> exactly. Returns 0 only then. For destructive
# steps where a stray keypress must not be enough.
confirm_typed() {
  local title=$1 text=$2 word=$3
  input_screen "$title" "$text" "" text \
    "Type ${word} and press enter to continue, or press esc to go back. Nothing has been written yet." \
    || return 1
  [[ $INPUT_VALUE == "$word" ]]
}
