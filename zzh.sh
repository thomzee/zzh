#!/usr/bin/env bash
#
# zzh — a fast SSH server launcher for your terminal (bash port).
#
# Pick a server from an fzf fuzzy list and hand off to a live ssh session.
# Sibling of the Go ../zzh; same creds.json schema and .zzh.yaml config.
#
# Sourcing this file (e.g. from test.sh) defines the functions without
# running main; executing it runs main.

set -u

# ── pure helpers (unit-tested) ──────────────────────────────────────────────

# server_port PORT — echo PORT, or 22 if empty/0.
server_port() {
  local p="${1:-}"
  if [[ -z "$p" || "$p" == "0" ]]; then
    echo 22
  else
    echo "$p"
  fi
}

# expand_home PATH — expand a leading ~ to $HOME.
expand_home() {
  local p="${1:-}"
  case "$p" in
    "~") echo "$HOME" ;;
    "~/"*) echo "$HOME/${p#\~/}" ;;
    *) echo "$p" ;;
  esac
}

# _zzh_have_sshpass — true if sshpass is on PATH. Overridable in tests.
_zzh_have_sshpass() { command -v sshpass >/dev/null 2>&1; }

# build_ssh_command NAME HOST USER PORT PASSWORD KEYPATH
# Populates globals ZZH_BIN and ZZH_ARGV with the command to exec.
# Returns non-zero (with a message on stderr) if it cannot build one.
#
# All ssh invocations pass StrictHostKeyChecking=accept-new: on the first
# connection to a host the key is trusted and recorded in known_hosts without
# an interactive prompt (which zzh can't answer — it hands off to ssh after
# fzf has consumed stdin, so the usual yes/no prompt would fail with "Host key
# verification failed"). A *changed* key is still refused, preserving the
# trust-on-first-use protection against MITM.
build_ssh_command() {
  local name="$1" host="$2" user="$3" port="$4" password="$5" keypath="$6"
  port="$(server_port "$port")"
  local target="${user}@${host}"
  local -a ssh_opts=(-o StrictHostKeyChecking=accept-new)

  if [[ -n "$keypath" ]]; then
    ZZH_BIN="ssh"
    ZZH_ARGV=(ssh "${ssh_opts[@]}" -i "$(expand_home "$keypath")" -p "$port" "$target")
  elif [[ -n "$password" ]]; then
    if ! _zzh_have_sshpass; then
      echo "error: sshpass not found on PATH (needed for password auth on \"$name\"); install it or use a keyPath" >&2
      return 1
    fi
    ZZH_BIN="sshpass"
    ZZH_ARGV=(sshpass -p "$password" ssh "${ssh_opts[@]}" -p "$port" "$target")
  else
    ZZH_BIN="ssh"
    ZZH_ARGV=(ssh "${ssh_opts[@]}" -p "$port" "$target")
  fi
}

# zzh_set_title NAME — label the terminal with the server NAME.
# Sets the tab/window title (baseline; a remote shell may overwrite it) and,
# under iTerm2, a badge: a large translucent watermark that persists for the
# whole session regardless of what the remote shell does.
zzh_set_title() {
  local name="$1"
  printf '\033]0;%s\007' "$name"
  if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
    printf '\033]1337;SetBadgeFormat=%s\007' "$(printf '%s' "$name" | base64)"
  fi
}

# zzh_clear_title — undo zzh_set_title (clear tab title and iTerm badge).
zzh_clear_title() {
  printf '\033]0;\007'
  if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
    printf '\033]1337;SetBadgeFormat=%s\007' ""
  fi
}

# config_creds_file YAML_FILE — echo the credsFile value (quotes stripped).
config_creds_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  # grab the value after "credsFile:", trim spaces, strip surrounding quotes
  local val
  val="$(grep -E '^[[:space:]]*credsFile:' "$file" | head -1 | sed -E 's/^[[:space:]]*credsFile:[[:space:]]*//')"
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  echo "$val"
}

# ── config discovery & loading ──────────────────────────────────────────────

# _zzh_first_existing FILE... — echo the first FILE that exists; non-zero if none.
_zzh_first_existing() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  return 1
}

# _zzh_resolve_dir SRC — resolve SRC through any symlinks and echo the directory
# of the real file. Lets zzh find its repo config even when invoked via a
# symlink on PATH (e.g. /opt/homebrew/bin/zzh -> .../riset/zzh/zzh.sh).
_zzh_resolve_dir() {
  local src="$1" dir
  while [[ -h "$src" ]]; do
    dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

# find_config — echo the first .zzh.yaml found, searching (in order): the real
# script directory, $HOME, $XDG_CONFIG_HOME/zzh, then the current directory.
find_config() {
  local script_dir
  script_dir="$(_zzh_resolve_dir "${BASH_SOURCE[0]}")"
  _zzh_first_existing \
    "$script_dir/.zzh.yaml" \
    "$HOME/.zzh.yaml" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/zzh/config.yaml" \
    "./.zzh.yaml"
}

# ── main ────────────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }

main() {
  command -v jq  >/dev/null 2>&1 || die "jq not found on PATH (install with: brew install jq)"
  command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH (install with: brew install fzf)"

  local config creds_file
  config="$(find_config)" || die "no .zzh.yaml found (next to zzh.sh or in the current directory)"
  creds_file="$(config_creds_file "$config")"
  [[ -n "$creds_file" ]] || die "credsFile not set in $config"
  [[ -f "$creds_file" ]] || die "creds file not found: $creds_file"

  local count
  count="$(jq 'length' "$creds_file" 2>/dev/null)" || die "could not parse $creds_file"
  [[ "$count" -gt 0 ]] || die "no servers found in $creds_file"

  # Build "name<TAB>user@host" lines for fzf; pick by name.
  local selection name
  selection="$(
    jq -r '.[] | "\(.name)\t\(.user)@\(.host)"' "$creds_file" |
      fzf --with-nth=1,2 --delimiter='\t' \
          --prompt='ssh > ' --height=40% --reverse \
          --header='Select a server — type to filter, enter to connect'
  )" || exit 0  # user pressed esc / ctrl-c
  [[ -n "$selection" ]] || exit 0

  name="${selection%%$'\t'*}"

  # Pull the chosen server's fields by exact name match.
  local host user port password keypath
  host="$(jq -r --arg n "$name" '.[] | select(.name==$n) | .host // ""' "$creds_file")"
  user="$(jq -r --arg n "$name" '.[] | select(.name==$n) | .user // ""' "$creds_file")"
  port="$(jq -r --arg n "$name" '.[] | select(.name==$n) | .port // ""' "$creds_file")"
  password="$(jq -r --arg n "$name" '.[] | select(.name==$n) | .password // ""' "$creds_file")"
  keypath="$(jq -r --arg n "$name" '.[] | select(.name==$n) | .keyPath // ""' "$creds_file")"

  build_ssh_command "$name" "$host" "$user" "$port" "$password" "$keypath" || exit 1

  echo "zzh connecting to ${name} (${user}@${host})"
  zzh_set_title "$name"
  # Clear the badge/title on ANY exit — normal logout, Ctrl-C, dropped
  # connection, or kill — so the local terminal is never left with a stale
  # badge. Run ssh as a child (not exec) so this cleanup can run.
  trap 'zzh_clear_title' EXIT INT TERM HUP
  "${ZZH_ARGV[@]}"
  exit "$?"
}

# Run main only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
