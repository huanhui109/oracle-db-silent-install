#!/usr/bin/env bash
# verify.sh - Post-install validation for a silent Oracle Database deployment.
#
# Usage (on target host as oracle user):
#   bash verify.sh [ORACLE_SID] [VERSION]
#   VERSION: 11g | 12c | 19c (default 19c); controls CDB-related checks.
#
# Usage via SSH alias (no secrets needed; uses OS auth / as sysdba):
#   ssh <alias> 'bash -s -- orcl 19c' < scripts/verify.sh
#
# SAFETY CONTRACT:
#   - Read-only SELECTs and status commands only. No DDL/DML, no shutdown.
#   - Never reads SSH keys, never prints passwords.

set -u
ORACLE_SID="${1:-${ORACLE_SID:-orcl}}"
VERSION="${2:-${VERSION:-19c}}"
VERSION="$(printf '%s' "$VERSION" | tr '[:upper:]' '[:lower:]')"
export ORACLE_SID

if [ -f /home/oracle/.bash_profile ]; then
  # shellcheck disable=SC1091
  . /home/oracle/.bash_profile >/dev/null 2>&1 || true
fi

hr() { printf '\n=== %s ===\n' "$1"; }
hr "VERIFY_META"
printf 'sid=%s\nprofile=%s\n' "$ORACLE_SID" "$VERSION"

hr "SQLPLUS_AVAILABILITY"
sqlplus -V 2>&1 | head -2 || { printf 'sqlplus NOT usable; check ORACLE_HOME/PATH\n'; exit 2; }

hr "INSTANCE_AND_DATABASE"
sqlplus -s / as sysdba <<'SQL'
set heading off feedback off pagesize 0
select 'INSTANCE_STATUS=' || status from v$instance;
select 'DB_NAME=' || name from v$database;
select 'DBID=' || dbid from v$database;
select 'OPEN_MODE=' || open_mode from v$database;
exit
SQL

hr "CDB_CHECK"
if [ "$VERSION" != "11g" ]; then
  sqlplus -s / as sysdba <<'SQL'
set heading off feedback off pagesize 0
select 'IS_CDB=' || cdb from v$database;
exit
SQL
  # PDB listing is only meaningful for CDB; query defensively.
  sqlplus -s / as sysdba <<'SQL' 2>/dev/null | grep -v '^$' || true
set heading off feedback off pagesize 0
select 'PDB=' || name || ' open=' || open_mode from v$pdbs;
exit
SQL
else
  printf 'IS_CDB=N/A (11g has no CDB architecture)\n'
fi

hr "CHARACTER_SET"
sqlplus -s / as sysdba <<'SQL'
set heading off feedback off pagesize 0
select 'CHARSET=' || value from nls_database_parameters where parameter='NLS_CHARACTERSET';
select 'NCHARSET=' || value from nls_database_parameters where parameter='NLS_NCHAR_CHARACTERSET';
exit
SQL

hr "MEMORY_PROCESSES"
sqlplus -s / as sysdba <<'SQL'
set heading off feedback off pagesize 0
select 'SGA_MB=' || round(value/1024/1024) from v$parameter where name='sga_target';
select 'PGA_MB=' || round(value/1024/1024) from v$parameter where name='pga_aggregate_target';
select 'PROCESSES=' || value from v$parameter where name='processes';
select 'MEMORY_TARGET_MB=' || round(value/1024/1024) from v$parameter where name='memory_target';
select 'LOCAL_LISTENER=' || value from v$parameter where name='local_listener';
exit
SQL

hr "LISTENER"
lsnrctl status 2>&1 | grep -E 'Alias|Listening on|status|Service "|Instance "|handler' | head -20
printf '%s\n' '--- port binding ---'
ss -lntp 2>/dev/null | grep -E ':1521|:1522' || netstat -lntp 2>/dev/null | grep -E ':1521|:1522' || printf 'no 1521/1522 listener found\n'

hr "NAME_RESOLUTION_FOR_LOCAL_LISTENER"
if [ -n "${ORACLE_HOME:-}" ] && [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
  grep -A3 -iE 'LISTENER_|LOCAL_LISTENER|ORCL' "$ORACLE_HOME/network/admin/tnsnames.ora" 2>/dev/null | head -20 || true
fi
tnsping "$ORACLE_SID" 2>&1 | tail -3 || true

hr "DISK_SPACE"
df -h /u01 "${ORACLE_HOME:-/u01}" 2>/dev/null | grep -vE '^Filesystem' || df -h / | tail -1

hr "ARCHIVE_RESIDUE"
printf 'zip_count_in_u01=%s\n' "$(find /u01 -maxdepth 1 -type f -iname '*.zip' 2>/dev/null | wc -l)"

hr "VERIFY_END"
