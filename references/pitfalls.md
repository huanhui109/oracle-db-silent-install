# Observed Pitfalls and Exact Fixes

Failure modes encountered in a real deployment, with the fix that worked.

## 1. dbca rejects memory keys with XSD error

**Symptom:**

```
[DBT-00108] Incorrect value passed to a command line argument.
CAUSE: cvc-complex-type.2.4.a: Invalid content was found starting with element 'memoryType'.
One of '{... initParams ... memoryPercentage ...}' is expected.
```

Response file contained `memoryType=AUTO`, `sgaTarget=512`, `pgaAggregateTarget=256`, `processes=100`.

**Root cause:** 19c (and 12.2+) dbca schema does not accept these keys. It expects `initParams`, `memoryPercentage`, `totalMemory`, `automaticMemoryManagement`.

**Fix:** Remove those four keys, add:

```
initParams=sga_target=512M,pga_aggregate_target=256M,processes=100
automaticMemoryManagement=FALSE
```

`scripts/gen_dbca_rsp.sh` emits the correct form per version. After the fix, dbca proceeded to 100% and created the database.

## 2. GLIBC_2.14 hard blocker on RHEL 6.7

**Symptom:** `ldd --version` = 2.12; `strings /lib64/libc.so.6 | grep -c '^GLIBC_2.14$'` = 0. Highest symbol `GLIBC_2.12`.

**Impact:** 19c binaries require GLIBC_2.14 at minimum. The installer may run with `-ignorePrereq`, but `sqlplus`/`oracle` will fail with `GLIBC_2.14 not found`. Installing is futile.

**Fix:** Build a new RHEL/OL/CentOS 7+ VM. Do not attempt in-place glibc upgrade unless the user supplies a trusted RPM, has a VMware snapshot, and accepts the risk of an unbootable OS.

## 3. `getent hosts` shows ::1 even though hosts file is correct

**Symptom:** `/etc/hosts` contains `192.168.10.128 localhost.localdomain`, but:

```
getent hosts localhost.localdomain   -> ::1  localhost
```

**Diagnosis:** `getent hosts` returns the first matching alias record (IPv6 loopback). Check authoritative signals:

```
hostname -f                          -> localhost.localdomain
getent ahosts localhost.localdomain  -> 192.168.10.128 ...
ping $(hostname)                     -> replies from 192.168.10.128
```

**Fix:** None needed if the above are correct. Do not keep editing `/etc/hosts`. This is a command-behavior artifact, not an Oracle blocker.

## 4. Missing compat-libstdc++-33 on CentOS 7 minimal

**Symptom:** Package absent from yum and from the mounted minimal ISO.

**Impact:** OUI prerequisite warning only for 19c, not a hard failure. `rpm -q` shows `package ... is not installed`.

**Fix:** Proceed with `-ignorePrereqFailure` after telling the user. If the user insists on installing it, source the RPM from a trusted repository or the full Oracle Linux media — do not fabricate a package.

## 5. `sysctl` not in PATH

**Symptom:** Running `sysctl -p` returns command not found on a minimal CentOS 7.

**Fix:** Use `/sbin/sysctl -p /etc/sysctl.d/99-oracle.conf`, or install `procps-ng` first. Preflight checks `/sbin/sysctl` presence.

## 6. netca response file path differs from plan

**Expectation from older docs:** `$ORACLE_HOME/install/response/netca.rsp`

**Actual on 19c:** `$ORACLE_HOME/assistants/netca/netca.rsp`

**Fix:** Probe both paths in preflight; use whichever exists. `netca -silent -responsefile ...` succeeded with the assistants path.

## 7. runInstaller returns code 6 despite success

**Symptom:** Output says `Successfully Setup Software with warning(s.)` but the SSH command returns non-zero.

**Cause in this environment:** local sandbox blocks `known_hosts` temp-file cleanup (`hostfile_replace_entries: unlink ... Permission denied`). This is a client-side artifact, not an install failure.

**Fix:** Verify success by checking `$ORACLE_HOME/bin/oracle` exists, no `FATAL` in the install log, and the root scripts were emitted — not by the SSH exit code alone.

## 8. sqlplus -V fails with absolute path

**Symptom:** `/u01/.../bin/sqlplus -V` errors when run without sourcing the oracle environment.

**Fix:** Always `source /home/oracle/.bash_profile` before invoking Oracle binaries. Verify with `sqlplus -V` (expect `19.3.0.0.0` in this case).

## 9. ORACLE_HOSTNAME / DECLINE_SECURITY_UPDATES missing from template

**Symptom:** Minimal 19c `db_install.rsp` template lacks these keys; silent install can hang prompting for MOS credentials.

**Fix:** Append explicitly:

```
ORACLE_HOSTNAME=<hostname>
DECLINE_SECURITY_UPDATES=true
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
oracle.installer.autoupdates.option=SKIP_UPDATES
```

`scripts/gen_db_install_rsp.sh` handles this and de-duplicates appended keys.

## 10. Listener bound to FQDN exposes the database on the network

**Symptom:** netca default binds to `localhost.localdomain`, which resolves to the VM's LAN IP (192.168.10.128), exposing 1521 on the VMnet8 segment.

**Fix:** Rewrite `listener.ora` with `HOST=127.0.0.1`, restart the listener, confirm `ss -lntp | grep 1521` shows only `127.0.0.1:1521`, and point `tnsnames.ora` / `local_listener` at loopback.

## 11. Tight disk after unzip

**Symptom:** Free space drops from ~16 GB to ~8.7 GB after unzipping 19c into ORACLE_HOME. dbca datafiles then push it lower.

**Fix:** Delete only the install ZIP (`rm -f /u01/LINUX.X64_193000_db_home.zip`) after software verification and before dbca. Never delete `oradata`. After cleanup in the real deployment, free space returned to ~8.6 GB.

## 12. Password handling

**Risk:** Putting real passwords into a response file via the agent, or copying them into chat.

**Fix:** `scripts/gen_dbca_rsp.sh` writes placeholders only. `scripts/fill_dbca_passwords.sh` uses `read -s` and must be run interactively by the user in the target terminal. Verify by counting remaining placeholders (`grep -c CHANGE_ME`), never by `cat` of the response file. If output must be captured, filter known secret values with sed `s/<value>/***/g` before displaying.
