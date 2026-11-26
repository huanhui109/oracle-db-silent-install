#!/usr/bin/env bash
# fill_dbca_passwords.sh - INTERACTIVELY replace password placeholders in a dbca rsp.
#
# Usage (run directly in the oracle user's terminal on the target host):
#   bash fill_dbca_passwords.sh /home/oracle/dbca.rsp
#
# This script MUST be run interactively by a human, not piped through an agent
# or automation, because:
#   1. It reads secrets with `read -s` (no terminal echo).
#   2. Secrets must never enter an agent conversation, command line, or log.
#
# SAFETY CONTRACT:
#   - Only edits the response file passed as $1.
#   - Does not print the entered passwords at any point.
#   - After editing, prints ONLY a count of remaining placeholders (not values).
#   - Never touches SSH keys.

set -eu
RSP="${1:?usage: fill_dbca_passwords.sh <dbca.rsp>}"
[ -f "$RSP" ] || { printf 'ERROR: response file not found: %s\n' "$RSP" >&2; exit 2; }
[ -t 0 ] || { printf 'ERROR: must run interactively from a terminal (stdin is not a TTY).\n' >&2; exit 3; }

printf 'Replacing SYS password placeholder...\n'
read -r -s -p 'SYS password: ' P1; printf '\n'
printf 'Replacing SYSTEM password placeholder...\n'
read -r -s -p 'SYSTEM password: ' P2; printf '\n'

# PDBADMIN is only required for CDB mode; fill it if the placeholder exists.
if grep -q '^pdbAdminPassword=__CHANGE_ME_PDBADMIN__$' "$RSP"; then
  printf 'Replacing PDBADMIN password placeholder...\n'
  read -r -s -p 'PDBADMIN password: ' P3; printf '\n'
else
  P3=''
fi

# Substitute into a temp file, then swap it in.
#
# Not `sed -i`: BSD sed consumes the argument after -i as a backup suffix, so the
# GNU form silently edits nothing on macOS. awk also means the password needs no
# sed-metacharacter escaping (`/`, `|`, `&` all just work).
umask 077
tmp="$RSP.tmp.$$"
awk -v s="$P1" -v y="$P2" -v p="$P3" '
  index($0, "sysPassword=") == 1     { print "sysPassword=" s; next }
  index($0, "systemPassword=") == 1  { print "systemPassword=" y; next }
  index($0, "pdbAdminPassword=") == 1 && p != "" { print "pdbAdminPassword=" p; next }
  { print }
' "$RSP" > "$tmp"
mv "$tmp" "$RSP"
chmod 600 "$RSP"
unset P1 P2 P3

remaining=$(grep -c 'CHANGE_ME' "$RSP" || true)
printf 'Remaining placeholders: %s (expected 0)\n' "$remaining"
printf 'Do NOT run `cat %s` — it would display the passwords.\n' "$RSP"
