#!/usr/bin/env bash
# gen_env_file.sh - Emit the oracle user's environment block (.bash_profile).
#
# Usage (on the target host as the oracle user):
#   bash gen_env_file.sh -                       # print to stdout
#   bash gen_env_file.sh /home/oracle/.bash_profile.block
#   bash gen_env_file.sh - | tee -a ~/.bash_profile
#
# Usage via an SSH alias from the controlling machine:
#   ssh <alias> 'bash -s -- - 19c' < scripts/gen_env_file.sh
#
# Environment overrides (all optional):
#   ORACLE_BASE      default /u01/app/oracle
#   ORACLE_HOME      default <ORACLE_BASE>/product/<ver>/dbhome_1
#   ORACLE_SID       default orcl
#   NLS_LANG         default AMERICAN_AMERICA.AL32UTF8
#   ORACLE_TMPDIR    default /tmp  (ambient TMPDIR is deliberately NOT used)
#   TNS_ADMIN        unset by default (Oracle uses ORACLE_HOME/network/admin)
#   VERSION          default 19c  (11g|12c|18c|19c) - only selects the default ORACLE_HOME
#
# SAFETY CONTRACT:
#   - Writes only the output path given as $1 (or stdout when $1 is "-").
#   - Contains no passwords, no hostnames of other machines, no key material.
#   - Does not modify .bash_profile in place; the caller decides how to append.

set -eu

OUT="${1:--}"
VERSION="${2:-${VERSION:-19c}}"
VERSION="$(printf '%s' "$VERSION" | tr '[:upper:]' '[:lower:]')"

ORACLE_BASE="${ORACLE_BASE:-/u01/app/oracle}"
case "$VERSION" in
  19c) DEFAULT_SUBDIR="product/19.0.0/dbhome_1" ;;
  18c) DEFAULT_SUBDIR="product/18.0.0/dbhome_1" ;;
  12c) DEFAULT_SUBDIR="product/12.2.0.1/dbhome_1" ;;
  11g) DEFAULT_SUBDIR="product/11.2.0/dbhome_1" ;;
  *)
    printf 'ERROR: unsupported VERSION=%s (use 11g|12c|18c|19c)\n' "$VERSION" >&2
    exit 2
    ;;
esac
ORACLE_HOME="${ORACLE_HOME:-${ORACLE_BASE}/${DEFAULT_SUBDIR}}"
ORACLE_SID="${ORACLE_SID:-orcl}"
NLS_LANG="${NLS_LANG:-AMERICAN_AMERICA.AL32UTF8}"
ORACLE_TMPDIR="${ORACLE_TMPDIR:-/tmp}"
TNS_ADMIN="${TNS_ADMIN:-}"

emit() {
  cat <<EOF
# >>> oracle-db-silent-install: environment (${VERSION}) >>>
# Managed block. Re-running the generator replaces this block; keep manual
# edits outside the markers.
umask 022
export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_HOME=${ORACLE_HOME}
export ORACLE_SID=${ORACLE_SID}
export PATH=\${ORACLE_HOME}/bin:\${PATH}
export LD_LIBRARY_PATH=\${ORACLE_HOME}/lib:\${LD_LIBRARY_PATH:-}
export NLS_LANG=${NLS_LANG}
export TMPDIR=${ORACLE_TMPDIR}
# NLS_LANG must match the database character set. ZHS16GBK databases normally
# use AMERICAN_AMERICA.ZHS16GBK, not AL32UTF8.
EOF
  if [ -n "$TNS_ADMIN" ]; then
    printf 'export TNS_ADMIN=%s\n' "$TNS_ADMIN"
  else
    printf '# export TNS_ADMIN=%s/network/admin\n' "$ORACLE_HOME"
  fi
  cat <<'EOF'
# <<< oracle-db-silent-install: environment <<<
EOF
}

if [ "$OUT" = "-" ]; then
  emit
  printf '# --- verification ---\n' >&2
  printf '# source ~/.bash_profile && sqlplus -V\n' >&2
else
  emit >"$OUT"
  chmod 644 "$OUT"
  printf 'GENERATED_ENV=%s\n' "$OUT"
  printf '%s\n' '--- effective settings ---'
  grep -E '^export (ORACLE_BASE|ORACLE_HOME|ORACLE_SID|NLS_LANG|TMPDIR)=' "$OUT"
  printf '%s\n' '--- append with: cat %s >> ~/.bash_profile && source ~/.bash_profile ---' "$OUT"
fi
