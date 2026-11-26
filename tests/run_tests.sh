#!/usr/bin/env bash
# run_tests.sh - Offline test suite for oracle-db-silent-install.
#
# Runs on macOS and Linux with plain bash (no bats, no Oracle, no network).
# It asserts the *contracts* that matter:
#   - every script parses
#   - generated response files carry the right keys per version
#   - no real secret can ever appear in a generated artifact
#   - destructive/shortcut paths (non-TTY password fill, bad version) fail closed
#
# Usage:
#   bash tests/run_tests.sh            # all tests
#   bash tests/run_tests.sh dbca       # only tests whose name matches "dbca"
#   make test

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT_DIR/scripts"
FIXTURES="$ROOT_DIR/tests/fixtures"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/odsitest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FILTER="${1:-}"
PASS=0
FAIL=0
SKIP=0
FAILED_LIST=""

ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED_LIST="${FAILED_LIST}
  - $1"; printf '  FAIL  %s\n' "$1"; if [ $# -gt 1 ]; then printf '        %s\n' "$2"; fi; }
skip() { SKIP=$((SKIP + 1)); printf '  skip  %s\n' "$1"; }

assert_eq() {
  # assert_eq <expected> <actual> <name>
  if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "expected [$1], got [$2]"; fi
}
assert_contains() {
  # assert_contains <file> <pattern> <name>
  if grep -qF -- "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3" "missing [$2] in $(basename "$1")"; fi
}
assert_not_contains() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then bad "$3" "unexpected [$2] in $(basename "$1")"; else ok "$3"; fi
}
assert_exit() {
  # assert_exit <expected> <actual> <name>
  if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "expected exit $1, got $2"; fi
}
assert_mode() {
  # assert_mode <file> <octal> <name>
  mode="$(ls -l "$1" 2>/dev/null | awk '{print $1}')"
  case "$mode" in
    "$2"*) ok "$3" ;;
    *)     bad "$3" "expected mode $2*, got ${mode:-missing}" ;;
  esac
}

# ---------------------------------------------------------------------------
# static checks
# ---------------------------------------------------------------------------
t01_syntax() {
  echo "[T01] bash -n on every script"
  local failed=0
  for f in "$SCRIPTS"/*.sh; do
    if ! bash -n "$f" 2>"$WORK/syntax.err"; then
      bad "syntax: $(basename "$f")" "$(cat "$WORK/syntax.err")"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ] && ok "all scripts parse"
}

t02_shellcheck() {
  echo "[T02] shellcheck (skipped when not installed)"
  if ! command -v shellcheck >/dev/null 2>&1; then
    skip "shellcheck not installed"
    return
  fi
  if shellcheck -S warning -x "$SCRIPTS"/*.sh >"$WORK/sc.out" 2>&1; then
    ok "shellcheck clean at warning level"
  else
    bad "shellcheck reported findings" "$(head -30 "$WORK/sc.out")"
  fi
}

t03_executable_bits() {
  echo "[T03] scripts are executable"
  local failed=0
  for f in "$SCRIPTS"/*.sh; do
    [ -x "$f" ] || { bad "not executable: $(basename "$f")"; failed=1; }
  done
  [ "$failed" -eq 0 ] && ok "all scripts carry +x"
}

# ---------------------------------------------------------------------------
# gen_dbca_rsp.sh
# ---------------------------------------------------------------------------
t10_dbca_19c_noncdb() {
  echo "[T10] dbca rsp: 19c non-CDB"
  bash "$SCRIPTS/gen_dbca_rsp.sh" "$WORK/dbca19.rsp" 19c >"$WORK/gen.out" 2>&1
  assert_exit 0 "$?" "generator exits 0"
  assert_contains "$WORK/dbca19.rsp" "responseFileVersion=/oracle/assistants/rspfmt_dbca_response_schema_v19.0.0" "schema version is v19.0.0"
  assert_contains "$WORK/dbca19.rsp" "initParams=sga_target=512M,pga_aggregate_target=256M,processes=100" "memory expressed via initParams"
  assert_contains "$WORK/dbca19.rsp" "automaticMemoryManagement=FALSE" "AMM disabled"
  assert_not_contains "$WORK/dbca19.rsp" "sgaTarget=" "no rejected sgaTarget key"
  assert_contains "$WORK/dbca19.rsp" "createAsContainerDatabase=false" "non-CDB toggle present"
  assert_eq "$(grep -c 'CHANGE_ME' "$WORK/dbca19.rsp")" "2" "exactly two password placeholders"
  assert_mode "$WORK/dbca19.rsp" "-rw-------" "response file is owner-only (600)"
}

t11_dbca_19c_cdb() {
  echo "[T11] dbca rsp: 19c CDB with one PDB"
  CDB_MODE=true PDB_NAME=orclpdb GDBNAME=orcl bash "$SCRIPTS/gen_dbca_rsp.sh" "$WORK/dbca19cdb.rsp" 19c >/dev/null 2>&1
  assert_exit 0 "$?" "generator exits 0"
  assert_contains "$WORK/dbca19cdb.rsp" "createAsContainerDatabase=true" "CDB toggle true"
  assert_contains "$WORK/dbca19cdb.rsp" "numberOfPDBs=1" "one PDB"
  assert_contains "$WORK/dbca19cdb.rsp" "pdbName=orclpdb" "PDB name honoured"
  assert_eq "$(grep -c 'CHANGE_ME' "$WORK/dbca19cdb.rsp")" "3" "three placeholders when CDB"
}

t12_dbca_11g() {
  echo "[T12] dbca rsp: 11g legacy key form"
  bash "$SCRIPTS/gen_dbca_rsp.sh" "$WORK/dbca11.rsp" 11g >/dev/null 2>&1
  assert_exit 0 "$?" "generator exits 0"
  assert_contains "$WORK/dbca11.rsp" "responseFileVersion=/oracle/assistants/rspfmt_dbca_response_schema_v11.2.0" "schema version is v11.2.0"
  assert_contains "$WORK/dbca11.rsp" "sgaTarget=512" "11g uses sgaTarget directly"
  assert_contains "$WORK/dbca11.rsp" "pgaAggregateTarget=256" "11g uses pgaAggregateTarget directly"
  assert_not_contains "$WORK/dbca11.rsp" "initParams=" "no initParams on 11g"
  assert_not_contains "$WORK/dbca11.rsp" "createAsContainerDatabase" "no CDB keys on 11g"
}

t13_dbca_18c() {
  echo "[T13] dbca rsp: 18c profile exists"
  bash "$SCRIPTS/gen_dbca_rsp.sh" "$WORK/dbca18.rsp" 18c >/dev/null 2>&1
  assert_exit 0 "$?" "generator exits 0"
  assert_contains "$WORK/dbca18.rsp" "rspfmt_dbca_response_schema_v18.0.0" "schema version is v18.0.0"
  assert_contains "$WORK/dbca18.rsp" "initParams=" "18c uses initParams like 19c"
}

t14_dbca_bad_version() {
  echo "[T14] dbca rsp: unsupported version fails closed"
  bash "$SCRIPTS/gen_dbca_rsp.sh" "$WORK/bad.rsp" 9i >/dev/null 2>&1
  assert_exit 2 "$?" "unknown version exits 2"
  if [ -f "$WORK/bad.rsp" ]; then bad "no file written on bad version"; else ok "no file written on bad version"; fi
}

# ---------------------------------------------------------------------------
# gen_db_install_rsp.sh
# ---------------------------------------------------------------------------
t20_install_rsp() {
  echo "[T20] install rsp: replace, append and de-duplicate"
  local home="$WORK/oh"
  mkdir -p "$home/install/response"
  cp "$FIXTURES/db_install.rsp.tpl" "$home/install/response/db_install.rsp"
  ORACLE_HOSTNAME=dbhost.example.com \
    bash "$SCRIPTS/gen_db_install_rsp.sh" "$home" "$WORK/db_install.rsp" 19c >"$WORK/gen2.out" 2>&1
  assert_exit 0 "$?" "generator exits 0"
  assert_contains "$WORK/db_install.rsp" "oracle.install.option=INSTALL_DB_SWONLY" "software-only option replaces the template value"
  assert_eq "$(grep -c '^oracle.install.option=' "$WORK/db_install.rsp")" "1" "no duplicate option key"
  assert_contains "$WORK/db_install.rsp" "ORACLE_HOSTNAME=dbhost.example.com" "ORACLE_HOSTNAME override applied"
  assert_eq "$(grep -c '^ORACLE_HOSTNAME=' "$WORK/db_install.rsp")" "1" "no duplicate ORACLE_HOSTNAME"
  assert_contains "$WORK/db_install.rsp" "DECLINE_SECURITY_UPDATES=true" "appended key that the template omitted"
  assert_contains "$WORK/db_install.rsp" "oracle.install.db.rootconfig.executeRootScript=false" "root script auto-exec disabled"
  assert_contains "$WORK/db_install.rsp" "INVENTORY_LOCATION=/u01/app/oraInventory" "inventory derived from ORACLE_BASE"
  assert_not_contains "$WORK/db_install.rsp" "INSTALL_DB_AND_CONFIG" "template default fully replaced"
}

t21_install_rsp_missing_template() {
  echo "[T21] install rsp: missing template fails closed"
  mkdir -p "$WORK/empty_home"
  bash "$SCRIPTS/gen_db_install_rsp.sh" "$WORK/empty_home" "$WORK/never.rsp" 19c >"$WORK/gen3.out" 2>&1
  assert_exit 2 "$?" "missing template exits 2"
  if [ -f "$WORK/never.rsp" ]; then bad "no output on missing template"; else ok "no output on missing template"; fi
}

# ---------------------------------------------------------------------------
# fill_dbca_passwords.sh
# ---------------------------------------------------------------------------
t30_fill_requires_tty() {
  echo "[T30] password fill refuses to run without a TTY"
  printf 'sysPassword=__CHANGE_ME_SYS__\nsystemPassword=__CHANGE_ME_SYSTEM__\n' >"$WORK/tty.rsp"
  bash "$SCRIPTS/fill_dbca_passwords.sh" "$WORK/tty.rsp" </dev/null >"$WORK/fill.out" 2>&1
  assert_exit 3 "$?" "non-TTY exits 3"
  assert_contains "$WORK/tty.rsp" "__CHANGE_ME_SYS__" "placeholders untouched after refusal"
}

t31_fill_missing_file() {
  echo "[T31] password fill rejects a missing response file"
  bash "$SCRIPTS/fill_dbca_passwords.sh" "$WORK/does-not-exist.rsp" </dev/null >/dev/null 2>&1
  assert_exit 2 "$?" "missing file exits 2"
}

# ---------------------------------------------------------------------------
# gen_env_file.sh
# ---------------------------------------------------------------------------
t40_env_file() {
  echo "[T40] environment block"
  bash "$SCRIPTS/gen_env_file.sh" "$WORK/profile.block" 19c >"$WORK/env.out" 2>&1
  assert_exit 0 "$?" "generator exits 0"
  assert_contains "$WORK/profile.block" "export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1" "19c home path"
  assert_contains "$WORK/profile.block" "export ORACLE_SID=orcl" "SID exported"
  assert_contains "$WORK/profile.block" 'export PATH=${ORACLE_HOME}/bin:${PATH}' "PATH prepends ORACLE_HOME/bin"
  assert_contains "$WORK/profile.block" "export TMPDIR=/tmp" "TMPDIR defaults to /tmp, not the caller's"
  assert_not_contains "$WORK/profile.block" "PASSWORD" "no secret vocabulary in the block"
}

t41_env_file_version() {
  echo "[T41] environment block honours 11g/12c homes"
  ORACLE_BASE=/u02/app/oracle bash "$SCRIPTS/gen_env_file.sh" "$WORK/p12.block" 12c >/dev/null 2>&1
  assert_contains "$WORK/p12.block" "ORACLE_HOME=/u02/app/oracle/product/12.2.0.1/dbhome_1" "12c path with custom base"
  bash "$SCRIPTS/gen_env_file.sh" "$WORK/p9.block" 9i >/dev/null 2>&1
  assert_exit 2 "$?" "unknown version exits 2"
}

# ---------------------------------------------------------------------------
# gen_listener_ora.sh
# ---------------------------------------------------------------------------
t50_listener_loopback() {
  echo "[T50] listener binds loopback by default"
  bash "$SCRIPTS/gen_listener_ora.sh" "$WORK/listener.ora" >"$WORK/lsnr.out" 2>&1
  assert_exit 0 "$?" "generator exits 0"
  assert_contains "$WORK/listener.ora" "(HOST = 127.0.0.1)(PORT = 1521)" "TCP address is loopback:1521"
  assert_contains "$WORK/listener.ora" "(KEY = EXTPROC1521)" "IPC key matches port"
  assert_contains "$WORK/listener.ora" "ADR_BASE_LISTENER = /u01/app/oracle" "ADR base emitted"
}

t51_listener_rewrite_backs_up() {
  echo "[T51] rewriting an existing listener.ora keeps a backup"
  printf 'LISTENER = (OLD)\n' >"$WORK/listener2.ora"
  bash "$SCRIPTS/gen_listener_ora.sh" "$WORK/listener2.ora" >/dev/null 2>&1
  local n
  n=$(ls "$WORK"/listener2.ora.bak.* 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "$n" "1" "one timestamped backup created"
}

t52_listener_exposure_warning() {
  echo "[T52] non-loopback bind is loudly warned"
  BIND_HOST=0.0.0.0 bash "$SCRIPTS/gen_listener_ora.sh" "$WORK/lan.ora" >"$WORK/lan.out" 2>&1
  assert_exit 0 "$?" "still generates the file"
  assert_contains "$WORK/lan.out" "WARN: BIND_HOST=0.0.0.0" "warning on stderr"
  assert_contains "$WORK/lan.ora" "(HOST = 0.0.0.0)" "requested bind honoured"
}

t53_listener_bad_port() {
  echo "[T53] listener rejects a non-numeric port"
  PORT=15x1 bash "$SCRIPTS/gen_listener_ora.sh" "$WORK/bad_lan.ora" >/dev/null 2>&1
  assert_exit 2 "$?" "non-numeric port exits 2"
}

t54_listener_tnsnames() {
  echo "[T54] tnsnames alias is emitted on request"
  TNS_OUT="$WORK/tnsnames.ora" SERVICE=orclpdb SID=orcl \
    bash "$SCRIPTS/gen_listener_ora.sh" "$WORK/l3.ora" >/dev/null 2>&1
  assert_contains "$WORK/tnsnames.ora" "LISTENER_ORCL =" "local_listener alias present"
  assert_contains "$WORK/tnsnames.ora" "(SERVICE_NAME = orclpdb)" "PDB service name honoured"
}

# ---------------------------------------------------------------------------
# gen_root_prep.sh
# ---------------------------------------------------------------------------
t60_root_prep_prints_only() {
  echo "[T60] root preparation block is printed, never executed"
  PHYSICAL_RAM_MB=4096 bash "$SCRIPTS/gen_root_prep.sh" 19c >"$WORK/root_prep.sh" 2>"$WORK/root_prep.err"
  assert_exit 0 "$?" "generator exits 0"
  assert_contains "$WORK/root_prep.sh" "getent group oinstall" "group creation is guarded (idempotent)"
  assert_contains "$WORK/root_prep.sh" "kernel.shmmax = 3221225472" "shmmax = 75% of 4096M RAM"
  assert_contains "$WORK/root_prep.sh" "kernel.shmall = 786432" "shmall = shmmax/4096"
  assert_contains "$WORK/root_prep.sh" "[ROOT 1/6]" "steps are numbered"
  assert_contains "$WORK/root_prep.sh" "yum install -y oracle-database-preinstall-19c" "preferred preinstall rpm"
  if bash -n "$WORK/root_prep.sh" 2>"$WORK/rp.err"; then ok "generated block is valid bash"; else bad "generated block is invalid bash" "$(cat "$WORK/rp.err")"; fi
}

t61_root_prep_unknown_ram() {
  echo "[T61] root preparation degrades to placeholders without /proc/meminfo"
  if [ -r /proc/meminfo ]; then
    skip "host has /proc/meminfo; placeholder path not reachable here"
    return
  fi
  bash "$SCRIPTS/gen_root_prep.sh" 19c >"$WORK/rp2.sh" 2>/dev/null
  assert_contains "$WORK/rp2.sh" "<RAM_KB_x_0.75_x_1024>" "explicit placeholder instead of a wrong number"
}

# ---------------------------------------------------------------------------
# show_plan.sh
# ---------------------------------------------------------------------------
t70_plan_stage_order() {
  echo "[T70] plan sheet lists all stages in order"
  HOST_ALIAS=orclvm bash "$SCRIPTS/show_plan.sh" 19c >"$WORK/plan.txt" 2>&1
  assert_exit 0 "$?" "generator exits 0"
  local last=0 stage line
  for stage in "Stage 0" "Stage 1" "Stage 2" "Stage 3" "Stage 4" "Stage 5" "Stage 6"; do
    line=$(grep -n "^${stage} " "$WORK/plan.txt" | head -1 | cut -d: -f1)
    if [ -z "$line" ]; then
      bad "missing ${stage}"; return
    fi
    if [ "$line" -le "$last" ]; then
      bad "${stage} out of order"; return
    fi
    last=$line
  done
  ok "stages 0-6 appear once each, in order"
  assert_contains "$WORK/plan.txt" "ssh orclvm 'bash -s -- 19c' < scripts/precheck.sh" "preflight command uses the real alias"
  assert_eq "$(grep -c '^CHECKPOINT [0-6]:' "$WORK/plan.txt")" "7" "one checkpoint per stage"
  assert_contains "$WORK/plan.txt" "[ROOT]" "root ownership of privileged steps is explicit"
}

t71_plan_11g_differences() {
  echo "[T71] plan sheet adapts to 11g"
  CDB_MODE=true bash "$SCRIPTS/show_plan.sh" 11g >"$WORK/plan11.txt" 2>&1
  assert_exit 0 "$?" "generator exits 0"
  assert_contains "$WORK/plan11.txt" "CDB_MODE     = false (N/A on 11g)" "CDB forced off on 11g"
  assert_not_contains "$WORK/plan11.txt" "-ignorePreReqs" "11g does not pass -ignorePreReqs to dbca"
}

# ---------------------------------------------------------------------------
# precheck.sh / verify.sh smoke
# ---------------------------------------------------------------------------
t80_precheck_smoke() {
  echo "[T80] preflight script completes and emits a verdict"
  bash "$SCRIPTS/precheck.sh" 19c >"$WORK/precheck.out" 2>/dev/null
  assert_exit 0 "$?" "preflight exits 0 on this host"
  assert_contains "$WORK/precheck.out" "=== END_OF_PRECHECK ===" "closing marker present"
  assert_contains "$WORK/precheck.out" "=== AUTO_VERDICT ===" "verdict section present"
}

t81_verify_portability() {
  echo "[T81] verify.sh survives an unset ORACLE_HOME"
  ( unset ORACLE_HOME; ORACLE_SID=orcl bash "$SCRIPTS/verify.sh" orcl 19c >"$WORK/verify.out" 2>&1 )
  local code=$?
  # Without sqlplus it must fail with its own message, not a bash unbound-variable crash.
  if grep -q "unbound variable" "$WORK/verify.out"; then
    bad "verify.sh crashed on unset ORACLE_HOME"
  else
    ok "no unbound-variable crash (exit $code)"
  fi
}

# ---------------------------------------------------------------------------
# security contracts across the whole repo
# ---------------------------------------------------------------------------
t90_no_literal_secrets() {
  echo "[T90] no artifact can carry a literal password"
  local offender=0 f line
  for f in "$ROOT_DIR"/examples/*/*.rsp "$WORK"/dbca19.rsp "$WORK"/dbca19cdb.rsp; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      case "$line" in
        *sysPassword=*|*systemPassword=*|*pdbAdminPassword=*)
          case "$line" in
            *__CHANGE_ME_*) : ;;
            *) bad "literal password in $(basename "$f")"; offender=1 ;;
          esac
          ;;
      esac
    done <"$f"
  done
  [ "$offender" -eq 0 ] && ok "every password field is a __CHANGE_ME_*__ placeholder"
}

t91_no_key_material() {
  echo "[T91] no private key material in the repository"
  if grep -rlE 'BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY' "$ROOT_DIR" >"$WORK/keys.out" 2>/dev/null; then
    bad "private key found" "$(cat "$WORK/keys.out")"
  else
    ok "no private key blocks"
  fi
}

t92_docs_present() {
  echo "[T92] required reader-facing docs exist"
  local missing=0 doc
  for doc in README.md README.zh-CN.md INSTALL.md CONTRIBUTING.md SECURITY.md CHANGELOG.md LICENSE SKILL.md; do
    if [ ! -f "$ROOT_DIR/$doc" ]; then bad "missing $doc"; missing=1; fi
  done
  [ "$missing" -eq 0 ] && ok "all top-level docs present"
}

# ---------------------------------------------------------------------------
# runner
# ---------------------------------------------------------------------------
TESTS="t01_syntax t02_shellcheck t03_executable_bits
t10_dbca_19c_noncdb t11_dbca_19c_cdb t12_dbca_11g t13_dbca_18c t14_dbca_bad_version
t20_install_rsp t21_install_rsp_missing_template
t30_fill_requires_tty t31_fill_missing_file
t40_env_file t41_env_file_version
t50_listener_loopback t51_listener_rewrite_backs_up t52_listener_exposure_warning t53_listener_bad_port t54_listener_tnsnames
t60_root_prep_prints_only t61_root_prep_unknown_ram
t70_plan_stage_order t71_plan_11g_differences
t80_precheck_smoke t81_verify_portability
t90_no_literal_secrets t91_no_key_material t92_docs_present"

printf 'oracle-db-silent-install test suite\n'
printf 'root: %s\n' "$ROOT_DIR"
printf 'bash: %s\n\n' "$BASH_VERSION"

for t in $TESTS; do
  case "$t" in
    *"$FILTER"*) "$t" ;;
  esac
done

printf '\n----------------------------------------\n'
printf 'passed %d   failed %d   skipped %d\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -ne 0 ]; then
  printf 'failures:%s\n' "$FAILED_LIST"
  exit 1
fi
printf 'all green\n'
