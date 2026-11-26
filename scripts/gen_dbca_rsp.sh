#!/usr/bin/env bash
# gen_dbca_rsp.sh - Generate a silent dbca response file (CDB or non-CDB).
#
# Usage (run on target host as the oracle user):
#   bash gen_dbca_rsp.sh <OUTPUT_RSP> [VERSION]
#
# Environment overrides (all optional):
#   GDBNAME           default orcl
#   SID               default $GDBNAME
#   CHARSET           default ZHS16GBK
#   NCHARSET          default AL16UTF16
#   DATAFILE_DEST     default /u01/app/oracle/oradata
#   RECOVERY_DEST     default empty
#   LISTENERS         default LISTENER
#   CDB_MODE          default false   (true|false; ignored on 11g)
#   PDB_NAME          default ${GDBNAME}pdb (used only when CDB_MODE=true)
#   SGA_MB            default 512
#   PGA_MB            default 256
#   PROCESSES         default 100
#   EDITION_TYPE      default GENERAL_PURPOSE
#   VERSION           default 19c  (11g|12c|18c|19c)
#
# SECURITY CONTRACT:
#   - Passwords are written ONLY as placeholders (__CHANGE_ME_SYS__ /
#     __CHANGE_ME_SYSTEM__ / __CHANGE_ME_PDBADMIN__). NO real password is
#     ever written by this script, printed, or accepted as an argument.
#   - Fill passwords on the target host with fill_dbca_passwords.sh (interactive,
#     no echo) so secrets never pass through an agent conversation or logs.
#   - Never touches SSH keys.

set -eu
OUT="${1:?usage: gen_dbca_rsp.sh <OUTPUT_RSP> [VERSION]}"
VERSION="${2:-${VERSION:-19c}}"
VERSION="$(printf '%s' "$VERSION" | tr '[:upper:]' '[:lower:]')"

GDBNAME="${GDBNAME:-orcl}"
SID="${SID:-$GDBNAME}"
CHARSET="${CHARSET:-ZHS16GBK}"
NCHARSET="${NCHARSET:-AL16UTF16}"
DATAFILE_DEST="${DATAFILE_DEST:-/u01/app/oracle/oradata}"
RECOVERY_DEST="${RECOVERY_DEST:-}"
LISTENERS="${LISTENERS:-LISTENER}"
CDB_MODE="${CDB_MODE:-false}"
PDB_NAME="${PDB_NAME:-${GDBNAME}pdb}"
SGA_MB="${SGA_MB:-512}"
PGA_MB="${PGA_MB:-256}"
PROCESSES="${PROCESSES:-100}"
EDITION_TYPE="${EDITION_TYPE:-GENERAL_PURPOSE}"

case "$VERSION" in
  19c) RSVP_VER='/oracle/assistants/rspfmt_dbca_response_schema_v19.0.0' ;;
  18c) RSVP_VER='/oracle/assistants/rspfmt_dbca_response_schema_v18.0.0' ;;
  12c) RSVP_VER='/oracle/assistants/rspfmt_dbca_response_schema_v12.2.0' ;;
  11g) RSVP_VER='/oracle/assistants/rspfmt_dbca_response_schema_v11.2.0' ;;
  *) printf 'ERROR: unsupported VERSION=%s (use 11g|12c|18c|19c)\n' "$VERSION" >&2; exit 2 ;;
esac

{
  printf 'responseFileVersion=%s\n' "$RSVP_VER"
  printf 'gdbName=%s\n' "$GDBNAME"
  printf 'sid=%s\n' "$SID"
  printf 'databaseConfigType=SI\n'
  printf 'templateName=General_Purpose.dbc\n'
  printf 'sysPassword=__CHANGE_ME_SYS__\n'
  printf 'systemPassword=__CHANGE_ME_SYSTEM__\n'

  if [ "$VERSION" != "11g" ]; then
    # 12c/19c: explicit CDB toggle. non-CDB is still valid in 19c (last version to support it).
    if [ "$CDB_MODE" = "true" ]; then
      printf 'createAsContainerDatabase=true\n'
      printf 'numberOfPDBs=1\n'
      printf 'pdbName=%s\n' "$PDB_NAME"
      printf 'pdbAdminPassword=__CHANGE_ME_PDBADMIN__\n'
      printf 'useLocalUndoForPDBs=true\n'
    else
      printf 'createAsContainerDatabase=false\n'
    fi
  fi

  printf 'datafileDestination=%s\n' "$DATAFILE_DEST"
  printf 'recoveryAreaDestination=%s\n' "$RECOVERY_DEST"
  printf 'storageType=FS\n'
  printf 'characterSet=%s\n' "$CHARSET"
  printf 'nationalCharacterSet=%s\n' "$NCHARSET"
  printf 'listeners=%s\n' "$LISTENERS"
  printf 'sampleSchema=false\n'
  printf 'databaseType=%s\n' "$EDITION_TYPE"
  printf 'enableArchive=false\n'
  printf 'runCVUChecks=false\n'

  # CRITICAL VERSION DIFFERENCE:
  #   19c/12c dbca schema does NOT accept sgaTarget / pgaAggregateTarget / processes /
  #   memoryType. It rejects them with cvc-complex-type.2.4.a XSD errors.
  #   Use comma-separated initParams + automaticMemoryManagement=FALSE instead.
  #   11g dbca accepts sgaTarget / pgaAggregateTarget / processes directly.
  case "$VERSION" in
    19c|18c|12c)
      printf 'initParams=sga_target=%sM,pga_aggregate_target=%sM,processes=%s\n' "$SGA_MB" "$PGA_MB" "$PROCESSES"
      printf 'automaticMemoryManagement=FALSE\n'
      ;;
    11g)
      printf 'sgaTarget=%s\n' "$SGA_MB"
      printf 'pgaAggregateTarget=%s\n' "$PGA_MB"
      printf 'processes=%s\n' "$PROCESSES"
      printf 'automaticMemoryManagement=FALSE\n'
      ;;
  esac
} > "$OUT"
chmod 600 "$OUT"

printf 'GENERATED_RSP=%s\n' "$OUT"
printf '%s\n' '--- key settings (passwords shown as placeholders only) ---'
grep -E '^(responseFileVersion|gdbName|sid|createAsContainerDatabase|numberOfPDBs|pdbName|characterSet|nationalCharacterSet|initParams|sgaTarget|pgaAggregateTarget|processes|automaticMemoryManagement|sysPassword|systemPassword|pdbAdminPassword)=' "$OUT" | sed -E 's/=(__CHANGE_ME_[^ ]*)$/=***/'
printf '%s\n' '--- fill passwords with: bash fill_dbca_passwords.sh %s ---' "$OUT"
