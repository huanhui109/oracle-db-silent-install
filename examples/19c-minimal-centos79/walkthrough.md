# Walkthrough: 19c, minimal, non-CDB, local-only

A stage-by-stage account of the deployment these artifacts come from: Oracle 19c
on CentOS 7.9, single non-CDB instance, SGA 512M / PGA 256M, listener bound to
loopback. Every file in this directory is produced by a script in `scripts/` —
none of it was typed by hand, which is the point: the same inputs must always
produce the same response files.

| File | Produced by | What it shows |
|---|---|---|
| `parameters.env` | hand-written | the single source of truth for this profile |
| `bash_profile.block` | `gen_env_file.sh` | oracle user environment |
| `root_prep.sh` | `gen_root_prep.sh` | printable root block (never executed by the tool) |
| `db_install.receipt` | `gen_db_install_rsp.sh` | effective keys in the install response file |
| `dbca.rsp` | `gen_dbca_rsp.sh` | full database response file, passwords still placeholders |
| `listener.ora` | `gen_listener_ora.sh` | loopback-only listener |
| `tnsnames.ora` | `gen_listener_ora.sh` | `LISTENER_ORCL` + service alias |
| `plan-19c.txt` | `show_plan.sh` | the review sheet a human approves |

Regenerate everything from scratch:

```bash
cd examples/19c-minimal-centos79
set -a; . ./parameters.env; set +a
bash ../../scripts/gen_env_file.sh bash_profile.block "$VERSION"
bash ../../scripts/gen_root_prep.sh "$VERSION" > root_prep.sh
bash ../../scripts/gen_dbca_rsp.sh dbca.rsp "$VERSION"
TNS_OUT=tnsnames.ora bash ../../scripts/gen_listener_ora.sh listener.ora
bash ../../scripts/show_plan.sh "$VERSION" > "plan-$VERSION.txt"
```

---

## Stage 0 — Preflight found the real blocker first

```bash
ssh orcl19c 'bash -s -- 19c' < scripts/precheck.sh
```

The survey is deliberately verbose: OS, glibc symbols, RAM/CPU/disk/inodes,
hostname resolution, users and groups, missing RPMs, kernel parameters, limits,
SELinux/firewall, existing Oracle state, and the install archive.

On a *different* VM this step ended the project before it started:

```
GLIBC_2.14_symbols=0
highest_glibc_symbol=GLIBC_2.12
BLOCKER: glibc lacks GLIBC_2.14 - 19c/18c/12.2+ binaries will not run.
```

19c binaries need the `GLIBC_2.14` symbol. glibc 2.12 (RHEL/CentOS 6) does not
have it, and no installer flag fixes a missing dynamic symbol — `-ignorePrereq`
only silences the check. The only honest answers are "use a 7+ OS" or "install
11g". That is why the preflight runs before anyone touches the filesystem.

On CentOS 7.9 the same section reports `GLIBC_2.14_symbols=1` and the plan can
proceed.

## Stage 1 — The plan a human actually approves

`plan-19c.txt` is that artifact: parameters at the top, then seven stages, each
tagged `[AGENT]`, `[ROOT]` or `[ORACLE]`, each ending in a `CHECKPOINT`. The
split is the safety model — privileged steps are handed over as text, not
executed silently.

## Stage 2 — Root preparation

```bash
bash scripts/gen_root_prep.sh 19c > root_prep.sh   # prints, does not run
# review, then as root on the target:
bash root_prep.sh
```

It computes `kernel.shmmax` and `kernel.shmall` from physical RAM (75% and
`shmmax/4096`), guards every creation step with `getent`, and prefers Oracle's
own `oracle-database-preinstall-19c` RPM before falling back to the explicit
package list.

### The hostname trap

`/etc/hosts` was correct, yet:

```
getent hosts localhost.localdomain   ->  ::1  localhost
hostname -f                          ->  localhost.localdomain
getent ahosts localhost.localdomain  ->  192.168.10.128 ...
ping $(hostname)                     ->  replies from 192.168.10.128
```

`getent hosts` returns the first matching alias and can surface the IPv6
loopback. Judging by it alone sends you editing a file that was never wrong.
The preflight prints all four signals for exactly this reason.

## Stage 3 — Software install

```bash
bash scripts/gen_env_file.sh - 19c | tee -a /home/oracle/.bash_profile
source /home/oracle/.bash_profile

unzip -q /u01/LINUX.X64_193000_db_home.zip -d "$ORACLE_HOME"   # image-based media

bash scripts/gen_db_install_rsp.sh "$ORACLE_HOME" /home/oracle/db_install.rsp 19c
cd "$ORACLE_HOME"
./runInstaller -silent -responseFile /home/oracle/db_install.rsp \
  -ignorePrereqFailure -waitforcompletion
```

Two details worth knowing before you run it:

- The image-based zip unpacks **into** an empty `ORACLE_HOME`. Unpacking to a
  parent directory and moving the tree afterwards breaks the installer.
- Minimal templates omit `ORACLE_HOSTNAME`, `DECLINE_SECURITY_UPDATES` and
  `SECURITY_UPDATES_VIA_MYORACLESUPPORT`. Without them a "silent" install can
  stop and wait for My Oracle Support credentials. The generator appends them
  and de-duplicates the result — see `db_install.receipt`.

Disk arithmetic on a 23 GB root partition: 16 GB free → ~8.7 GB after unpacking
→ lower still once datafiles are created. `references/planning.md` carries the
budget table.

## Stage 4 — Root scripts

`runInstaller` prints two paths; run them as root, in this order:

```bash
/u01/app/oraInventory/orainstRoot.sh
$ORACLE_HOME/root.sh
```

`root.sh` can return a non-zero code while the install is fine. Judge by
`$ORACLE_HOME/bin/oracle` existing, no `FATAL` in the installer log, and the root
scripts having been emitted — not by the exit code alone.

## Stage 5 — Listener, then database

```bash
netca -silent -responsefile "$ORACLE_HOME/assistants/netca/netca.rsp"
```

Note the path: `assistants/netca/netca.rsp`, **not** `install/response/netca.rsp`
as older documentation claims. Probe both.

Default `netca` binds to the FQDN, which on this VM resolved to the LAN address —
the database was reachable from the VMnet8 segment. For local-only testing:

```bash
TNS_OUT="$ORACLE_HOME/network/admin/tnsnames.ora" \
  bash scripts/gen_listener_ora.sh "$ORACLE_HOME/network/admin/listener.ora"
lsnrctl reload
ss -lntp | grep 1521     # expect 127.0.0.1:1521 only
```

Then the database. The parameters are generated; the passwords are typed by a
human into that terminal:

```bash
bash scripts/gen_dbca_rsp.sh /home/oracle/dbca.rsp 19c
bash scripts/fill_dbca_passwords.sh /home/oracle/dbca.rsp   # read -s, no echo
dbca -silent -createDatabase -responseFile /home/oracle/dbca.rsp
```

`fill_dbca_passwords.sh` refuses to run without a TTY — that is a feature, and
the test suite asserts it (`tests/run_tests.sh`, T30). If an agent ever pipes
into it, the script exits 3 and the placeholders stay untouched.

### The most common 19c failure

Reusing 11g-era memory keys:

```
cvc-complex-type.2.4.a: Invalid content was found starting with element 'memoryType'.
```

19c/12.2+ `dbca` does not accept `memoryType`, `sgaTarget`, `pgaAggregateTarget`
or `processes`. It wants them inside `initParams` plus
`automaticMemoryManagement=FALSE`:

```
initParams=sga_target=512M,pga_aggregate_target=256M,processes=100
automaticMemoryManagement=FALSE
```

`dbca.rsp` in this directory shows the correct 19c form; `../11g-legacy-rhel6/`
shows the legacy form. Comparing the two files side by side is the fastest way
to see why the generator branches on version at all.

If startup then fails with `ORA-00838`, SGA is below the practical floor: raise
it to 640M in the rsp and recreate (or `ALTER SYSTEM` if the instance comes up).

## Stage 6 — Verify, then clean up

```bash
ssh orcl19c 'bash -s -- orcl 19c' < scripts/verify.sh
```

Require all of: instance `OPEN`, `IS_CDB` matching the plan, charset as planned,
SGA/PGA/processes as planned, listener bound where intended, `tnsping` OK.

Only then delete the install zip — that one file:

```bash
rm -f /u01/LINUX.X64_193000_db_home.zip
df -h /u01        # 19c cleanup returned ~8.6 GB free on this VM
```

Never `rm -rf` an `oradata` directory. A failed `dbca` leaves partial files;
confirm `ps -ef | grep pmon` shows the instance down before touching anything,
and remove only the specific `<SID>` directory.

---

## What to copy, what to change

Copy: the stage order, the tags, the version-specific response-file keys.

Change: every absolute path, the SID, the charset, the memory numbers, and the
listener bind address. `parameters.env` is the only file you should need to edit
before regenerating the rest.
