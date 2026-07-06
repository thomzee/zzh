#!/usr/bin/env bash
# Minimal test harness for zzh.sh — no external deps (no bats required).
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=zzh.sh
source "$DIR/zzh.sh"

pass=0
fail=0

ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }

assert_eq() { # desc want got
  if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1" "want [$2] got [$3]"; fi
}

assert_argv() { # desc want(space-joined) — compares against ZZH_ARGV
  local got="${ZZH_ARGV[*]}"
  assert_eq "$1" "$2" "$got"
}

# ── server_port ────────────────────────────────────────────────────────────
assert_eq "port defaults to 22" "22" "$(server_port "")"
assert_eq "port defaults to 22 for 0" "22" "$(server_port "0")"
assert_eq "port passthrough" "2222" "$(server_port "2222")"

# ── expand_home ────────────────────────────────────────────────────────────
assert_eq "expand_home ~/x" "$HOME/.ssh/id" "$(expand_home "~/.ssh/id")"
assert_eq "expand_home absolute" "/abs/path" "$(expand_home "/abs/path")"
assert_eq "expand_home empty" "" "$(expand_home "")"

# ── build_ssh_command: key auth ────────────────────────────────────────────
build_ssh_command "prod" "h" "u" "2222" "" "/keys/id"
assert_eq "key auth bin" "ssh" "$ZZH_BIN"
assert_argv "key auth argv" "ssh -o StrictHostKeyChecking=accept-new -i /keys/id -p 2222 u@h"

# ── build_ssh_command: key auth expands ~ ──────────────────────────────────
build_ssh_command "prod" "h" "u" "" "" "~/id"
assert_argv "key auth expands home" "ssh -o StrictHostKeyChecking=accept-new -i $HOME/id -p 22 u@h"

# ── build_ssh_command: no auth ─────────────────────────────────────────────
build_ssh_command "bastion" "h" "u" "2200" "" ""
assert_eq "no auth bin" "ssh" "$ZZH_BIN"
assert_argv "no auth argv" "ssh -o StrictHostKeyChecking=accept-new -p 2200 u@h"

# ── build_ssh_command: password auth (sshpass present) ─────────────────────
_zzh_have_sshpass() { return 0; }
build_ssh_command "prod" "h" "u" "22" "pw" ""
assert_eq "password auth bin" "sshpass" "$ZZH_BIN"
assert_argv "password auth argv" "sshpass -p pw ssh -o StrictHostKeyChecking=accept-new -p 22 u@h"

# ── build_ssh_command: password auth (sshpass missing) ─────────────────────
_zzh_have_sshpass() { return 1; }
if build_ssh_command "prod" "h" "u" "22" "pw" "" 2>/dev/null; then
  no "password auth fails without sshpass" "expected non-zero exit"
else
  ok "password auth fails without sshpass"
fi

# ── set_title / clear_title ────────────────────────────────────────────────
out="$(TERM_PROGRAM=iTerm.app zzh_set_title "myserver")"
case "$out" in
  *myserver*) ok "set_title sets tab title to name" ;;
  *) no "set_title sets tab title to name" "got [$out]" ;;
esac
badge="$(printf '%s' "myserver" | base64)"
case "$out" in
  *"$badge"*) ok "set_title emits iTerm badge (base64 name)" ;;
  *) no "set_title emits iTerm badge (base64 name)" "missing [$badge] in [$out]" ;;
esac
# non-iTerm: still sets the tab title, but no badge sequence
out="$(TERM_PROGRAM=Apple_Terminal zzh_set_title "myserver")"
case "$out" in
  *SetBadgeFormat*) no "non-iTerm skips badge" "unexpected badge in [$out]" ;;
  *myserver*) ok "non-iTerm still sets tab title" ;;
  *) no "non-iTerm still sets tab title" "got [$out]" ;;
esac
# clear_title emits a SetBadgeFormat (to empty) under iTerm
out="$(TERM_PROGRAM=iTerm.app zzh_clear_title)"
case "$out" in
  *SetBadgeFormat*) ok "clear_title clears iTerm badge" ;;
  *) no "clear_title clears iTerm badge" "got [$out]" ;;
esac

# ── config_creds_file ──────────────────────────────────────────────────────
tmp="$(mktemp)"
printf 'credsFile: "/tmp/creds.json"\n' >"$tmp"
assert_eq "config quoted value" "/tmp/creds.json" "$(config_creds_file "$tmp")"
printf 'credsFile: /tmp/bare.json\n' >"$tmp"
assert_eq "config bare value" "/tmp/bare.json" "$(config_creds_file "$tmp")"
rm -f "$tmp"

# ── _zzh_first_existing ─────────────────────────────────────────────────────
d="$(mktemp -d)"
touch "$d/real"
assert_eq "first_existing picks first present" "$d/real" "$(_zzh_first_existing "$d/nope1" "$d/real" "$d/nope2")"
if _zzh_first_existing "$d/nope1" "$d/nope2" >/dev/null; then
  no "first_existing returns non-zero when none exist" "expected failure"
else
  ok "first_existing returns non-zero when none exist"
fi
rm -rf "$d"

# ── _zzh_resolve_dir (follows symlinks to the real script dir) ──────────────
# normalize to physical paths (macOS /var -> /private/var) since resolve_dir
# returns `pwd -P`
real="$(cd "$(mktemp -d)" && pwd -P)"; link="$(cd "$(mktemp -d)" && pwd -P)"
touch "$real/zzh.sh"
ln -s "$real/zzh.sh" "$link/zzh"
assert_eq "resolve_dir follows symlink" "$real" "$(_zzh_resolve_dir "$link/zzh")"
assert_eq "resolve_dir on real file" "$real" "$(_zzh_resolve_dir "$real/zzh.sh")"
rm -rf "$real" "$link"

# ── summary ─────────────────────────────────────────────────────────────────
echo
echo "passed: $pass  failed: $fail"
[[ "$fail" -eq 0 ]]
