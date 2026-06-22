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
build_ssh_command() {
  local name="$1" host="$2" user="$3" port="$4" password="$5" keypath="$6"
  port="$(server_port "$port")"
  local target="${user}@${host}"

  if [[ -n "$keypath" ]]; then
    ZZH_BIN="ssh"
    ZZH_ARGV=(ssh -i "$(expand_home "$keypath")" -p "$port" "$target")
  elif [[ -n "$password" ]]; then
    if ! _zzh_have_sshpass; then
      echo "error: sshpass not found on PATH (needed for password auth on \"$name\"); install it or use a keyPath" >&2
      return 1
    fi
    ZZH_BIN="sshpass"
    ZZH_ARGV=(sshpass -p "$password" ssh -p "$port" "$target")
  else
    ZZH_BIN="ssh"
    ZZH_ARGV=(ssh -p "$port" "$target")
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

# find_config — echo path to the first .zzh.yaml found (script dir, then cwd).
find_config() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$script_dir/.zzh.yaml" ]]; then echo "$script_dir/.zzh.yaml"; return 0; fi
  if [[ -f "./.zzh.yaml" ]]; then echo "./.zzh.yaml"; return 0; fi
  return 1
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
  # Run as a child (not exec) so we can clear the badge when the session ends.
  "${ZZH_ARGV[@]}"
  local rc=$?
  zzh_clear_title
  exit "$rc"
}

# Run main only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
