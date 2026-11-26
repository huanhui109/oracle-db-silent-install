#!/usr/bin/env bash
# gen_db_install_rsp.sh - Generate an Oracle software-only install response file.
#
# Usage (run on target host as the oracle user):
#   bash gen_db_install_rsp.sh <ORACLE_HOME> <OUTPUT_RSP> [VERSION]
#
# Environment overrides (all optional):
#   ORACLE_BASE       default /u01/app/oracle
#   ORACLE_HOSTNAME   default $(hostname)
#   INVENTORY_LOC     default $ORACLE_BASE/../oraInventory
#   UNIX_GROUP        default oinstall
#   DB_GROUP          default dba
#   OPER_GROUP        default oper
#   EDITION           default EE   (EE|SE2|SE)
#   SELECTED_LANG     default en
#   VERSION           default 19c  (11g|12c|18c|19c)
#
# SAFETY CONTRACT:
#   - Writes ONLY the output response file path given as $2.
#   - Contains no passwords (software-only install never needs DB passwords).
#   - Never touches SSH keys.
#   - Does not execute runInstaller; that is a separate, explicit step.

set -eu
ORACLE_HOME="${1:?usage: gen_db_install_rsp.sh <ORACLE_HOME> <OUTPUT_RSP> [VERSION]}"
OUT="${2:?usage: gen_db_install_rsp.sh <ORACLE_HOME> <OUTPUT_RSP> [VERSION]}"
VERSION="${3:-${VERSION:-19c}}"
VERSION="$(printf '%s' "$VERSION" | tr '[:upper:]' '[:lower:]')"

ORACLE_BASE="${ORACLE_BASE:-/u01/app/oracle}"
ORACLE_HOSTNAME="${ORACLE_HOSTNAME:-$(hostname)}"
INVENTORY_LOC="${INVENTORY_LOC:-$(dirname "$ORACLE_BASE")/oraInventory}"
UNIX_GROUP="${UNIX_GROUP:-oinstall}"
DB_GROUP="${DB_GROUP:-dba}"
OPER_GROUP="${OPER_GROUP:-oper}"
EDITION="${EDITION:-EE}"
SELECTED_LANG="${SELECTED_LANG:-en}"

TPL="$ORACLE_HOME/install/response/db_install.rsp"
if [ ! -f "$TPL" ]; then
  printf 'ERROR: template not found: %s\n' "$TPL" >&2
  printf 'For 19c image-based install the zip must be unzipped into ORACLE_HOME first.\n' >&2
  exit 2
fi
cp "$TPL" "$OUT"

# Escape replacement strings that may contain & or / or backslash or the |
# delimiter used by set_val's sed expression.
esc() { printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'; }

set_val() {
  # set_val <key> <value> : replace an existing (commented or not) key, else append.
  key="$1"; val="$(esc "$2")"
  if grep -qE "^#?${key}=" "$OUT"; then
    sed -i -E "s|^#?${key}=.*|${key}=${val}|" "$OUT"
  else
    printf '%s=%s\n' "$key" "$2" >> "$OUT"
  fi
}

# Keys common across 11g/12c/19c for software-only install.
set_val oracle.install.option INSTALL_DB_SWONLY
set_val ORACLE_HOSTNAME "$ORACLE_HOSTNAME"
set_val UNIX_GROUP_NAME "$UNIX_GROUP"
set_val INVENTORY_LOCATION "$INVENTORY_LOC"
set_val SELECTED_LANGUAGES "$SELECTED_LANG"
set_val ORACLE_HOME "$ORACLE_HOME"
set_val ORACLE_BASE "$ORACLE_BASE"
set_val oracle.install.db.InstallEdition "$EDITION"
set_val oracle.install.db.OSDBA_GROUP "$DB_GROUP"
set_val oracle.install.db.OSOPER_GROUP "$OPER_GROUP"
set_val oracle.install.db.OSBACKUPDBA_GROUP "$DB_GROUP"
set_val oracle.install.db.OSDGDBA_GROUP "$DB_GROUP"
set_val oracle.install.db.OSKMDBA_GROUP "$DB_GROUP"
set_val oracle.install.db.OSRACDBA_GROUP "$DB_GROUP"

# 12c/18c/19c: explicitly disable root script auto-execution; 11g uses different key.
case "$VERSION" in
  19c|18c|12c)
    set_val oracle.install.db.rootconfig.executeRootScript false
    set_val oracle.installer.autoupdates.option SKIP_UPDATES
    ;;
esac

# Security-update suppression. Minimal templates often omit these keys entirely.
set_val SECURITY_UPDATES_VIA_MYORACLESUPPORT false
set_val DECLINE_SECURITY_UPDATES true
set_val oracle.install.db.config.starterdb.type GENERAL_PURPOSE

# Ensure the suppressions exist even if set_val appended duplicates: keep last value only.
for k in DECLINE_SECURITY_UPDATES SECURITY_UPDATES_VIA_MYORACLESUPPORT ORACLE_HOSTNAME oracle.installer.autoupdates.option; do
  if [ "$(grep -c "^${k}=" "$OUT")" -gt 1 ]; then
    tmp="${OUT}.dedup.$$"
    awk -v key="$k" '
      index($0, key"=")==1 { if (seen[key]++) next }
      { print }
    ' "$OUT" > "$tmp" && mv "$tmp" "$OUT"
  fi
done

printf 'GENERATED_RSP=%s\n' "$OUT"
printf '%s\n' '--- key settings (no secrets present) ---'
grep -E '^(oracle.install.option|ORACLE_HOSTNAME|UNIX_GROUP_NAME|INVENTORY_LOCATION|ORACLE_HOME|ORACLE_BASE|oracle.install.db.InstallEdition|oracle.install.db.OSDBA_GROUP|oracle.install.db.OSOPER_GROUP|oracle.install.db.rootconfig.executeRootScript|DECLINE_SECURITY_UPDATES|oracle.installer.autoupdates.option)=' "$OUT" | sort
