#!/usr/bin/env bash
# show_plan.sh - Print the ordered, parameterized install plan (a review sheet).
#
# This is the artifact to hand a human before anything is executed: every step
# is tagged [AGENT] (automated, safe), [ROOT] (human runs as root) or
# [ORACLE] (human runs as the oracle user), and every stage ends in a
# CHECKPOINT that must be confirmed before the next stage starts.
#
# Usage:
#   bash show_plan.sh [VERSION]                 # stdout
#   bash show_plan.sh 19c > plan-19c.txt
#
# Environment overrides (all optional):
#   HOST_ALIAS   default <ssh-alias>   placeholder used in ssh examples
#   ORACLE_BASE  default /u01/app/oracle
#   ORACLE_HOME  default <ORACLE_BASE>/product/<ver>/dbhome_1
#   ORACLE_SID   default orcl
#   GDBNAME      default ${ORACLE_SID}
#   CHARSET      default ZHS16GBK
#   CDB_MODE     default false
#   SGA_MB / PGA_MB / PROCESSES   default 512 / 256 / 100
#   BIND_HOST / PORT              default 127.0.0.1 / 1521
#   VERSION                       default 19c  (11g|12c|18c|19c)
#
# SAFETY CONTRACT:
#   - Prints text only. Executes nothing, connects to nothing, writes no file
#     unless the caller redirects stdout.

set -eu

VERSION="${1:-${VERSION:-19c}}"
VERSION="$(printf '%s' "$VERSION" | tr '[:upper:]' '[:lower:]')"

HOST_ALIAS="${HOST_ALIAS:-<ssh-alias>}"
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
GDBNAME="${GDBNAME:-$ORACLE_SID}"
CHARSET="${CHARSET:-ZHS16GBK}"
CDB_MODE="${CDB_MODE:-false}"
SGA_MB="${SGA_MB:-512}"
PGA_MB="${PGA_MB:-256}"
PROCESSES="${PROCESSES:-100}"
BIND_HOST="${BIND_HOST:-127.0.0.1}"
PORT="${PORT:-1521}"

if [ "$VERSION" = "11g" ] && [ "$CDB_MODE" = "true" ]; then
  printf 'WARN: 11g has no CDB architecture; CDB_MODE=true will be ignored.\n' >&2
  CDB_MODE=false
fi

INVENTORY_LOC="${INVENTORY_LOC:-$(dirname "$ORACLE_BASE")/oraInventory}"
CDB_NOTE=""
DBCA_FLAGS=""
if [ "$VERSION" = "11g" ]; then
  CDB_NOTE=" (N/A on 11g)"
else
  DBCA_FLAGS=" -ignorePreReqs"
fi

cat <<EOF
Oracle Database ${VERSION} silent install - review sheet
========================================================
Generated: $(date '+%F %T %Z')
Target SSH alias: ${HOST_ALIAS}

Parameters under review
-----------------------
ORACLE_BASE  = ${ORACLE_BASE}
ORACLE_HOME  = ${ORACLE_HOME}
ORACLE_SID   = ${ORACLE_SID}
GDBNAME      = ${GDBNAME}
CHARSET      = ${CHARSET}
CDB_MODE     = ${CDB_MODE}${CDB_NOTE}
MEMORY       = SGA ${SGA_MB}M / PGA ${PGA_MB}M / processes ${PROCESSES}
LISTENER     = ${BIND_HOST}:${PORT}

Stage 0 - Preflight (read-only)                               [AGENT]
---------------------------------------------------------------
ssh ${HOST_ALIAS} 'bash -s -- ${VERSION}' < scripts/precheck.sh
Resolve every BLOCKER: line before continuing.
  - 19c/12c require the GLIBC_2.14 symbol; glibc 2.12 cannot run these binaries.
  - Note which RPMs are MISSING and whether the platform is outside Oracle support.

CHECKPOINT 0: report delivered, no blockers, plan not yet approved.

Stage 1 - Written plan and approval                           [AGENT]
---------------------------------------------------------------
Present: directory tree, space budget, exact parameters, root-vs-oracle split,
and explicit risk acceptance. Wait for an explicit "go".

CHECKPOINT 1: user approved the plan.

Stage 2 - System preparation (root)                           [ROOT]
---------------------------------------------------------------
bash scripts/gen_root_prep.sh ${VERSION} > /tmp/root_prep.sh
# review /tmp/root_prep.sh, then on the target as root:
#   bash /tmp/root_prep.sh
Verify: id ${OS_USER:-oracle}; hostname -f; /sbin/sysctl -p (already applied);
        ulimit -a as oracle.

CHECKPOINT 2: groups, directories, sysctl, limits and packages confirmed.

Stage 3 - Software install (oracle user)                      [ORACLE]
---------------------------------------------------------------
# 3.1 environment
bash scripts/gen_env_file.sh - ${VERSION} | tee -a /home/oracle/.bash_profile
source /home/oracle/.bash_profile

# 3.2 media - IMAGE-BASED zip goes straight into the empty ORACLE_HOME
unzip -q /u01/LINUX.X64_193000_db_home.zip -d "${ORACLE_HOME}"

# 3.3 response file and installer
bash scripts/gen_db_install_rsp.sh "${ORACLE_HOME}" /home/oracle/db_install.rsp ${VERSION}
cd "${ORACLE_HOME}"
./runInstaller -silent -responseFile /home/oracle/db_install.rsp \\
  -ignorePrereqFailure -waitforcompletion

CHECKPOINT 3: "Successfully Setup Software" and two root script paths captured.

Stage 4 - Root scripts                                        [ROOT]
---------------------------------------------------------------
${INVENTORY_LOC}/orainstRoot.sh
${ORACLE_HOME}/root.sh
Verify: /etc/oratab entry exists, root.sh log clean, sqlplus -V works as oracle.

CHECKPOINT 4: both root scripts succeeded.

Stage 5 - Listener and database (oracle user)                 [ORACLE]
---------------------------------------------------------------
# 5.1 listener (19c template lives under assistants/, not install/response/)
netca -silent -responsefile "${ORACLE_HOME}/assistants/netca/netca.rsp"

# 5.2 bind loopback for local-only testing
TNS_OUT="${ORACLE_HOME}/network/admin/tnsnames.ora" \\
  bash scripts/gen_listener_ora.sh "${ORACLE_HOME}/network/admin/listener.ora"
lsnrctl reload && ss -lntp | grep ${PORT}

# 5.3 database - passwords are typed by the human, never by an agent
bash scripts/gen_dbca_rsp.sh /home/oracle/dbca.rsp ${VERSION}
bash scripts/fill_dbca_passwords.sh /home/oracle/dbca.rsp
dbca -silent -createDatabase -responseFile /home/oracle/dbca.rsp${DBCA_FLAGS}

CHECKPOINT 5: dbca reached 100%, instance registered in /etc/oratab.

Stage 6 - Verification and cleanup                            [AGENT]
---------------------------------------------------------------
ssh ${HOST_ALIAS} 'bash -s -- ${ORACLE_SID} ${VERSION}' < scripts/verify.sh
Require: instance OPEN, CDB flag as planned, charset as planned, memory values
as planned, listener bound to ${BIND_HOST}:${PORT}, tnsping OK.
Only then delete the install zip as a single file:  rm -f /u01/*_db_home.zip

CHECKPOINT 6: verification green, cleanup done, free space reported.

Red lines
---------
- Never rm -rf an oradata directory.
- Never put a real password in a response file, a command line, or a chat message.
- Never display, copy or transmit SSH key material.
EOF
