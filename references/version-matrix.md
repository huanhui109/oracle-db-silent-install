# Version and Platform Matrix

Reference for choosing install strategy and response-file keys per Oracle version.

## glibc / OS hard floors

| Oracle version | Minimum glibc | Works on RHEL 6 (glibc 2.12)? | Notes |
|---|---|---|---|
| 11gR2 (11.2.0.4) | 2.5+ (2.12 OK) | Yes | 32-bit libs needed for some ops; old `pdksh` may be required |
| 12cR1 (12.1.0.2) | 2.12+ | Borderline | 12.1 needs GLIBC_2.12; verify with strings on libc.so.6 |
| 12cR2 (12.2+) / 18c / 19c | **2.14+** | **No** | `GLIBC_2.14` symbol absent on glibc 2.12 → binaries fail at runtime. Use RHEL/OL/CentOS 7+. |

Detection on target:

```bash
strings /lib64/libc.so.6 | grep -c '^GLIBC_2.14$'   # 19c/12.2+ require >= 1
strings /lib64/libc.so.6 | grep '^GLIBC_' | sort -V | tail -1
```

Never attempt to "upgrade glibc in place" on a production or primary test VM without a VMware snapshot — it can render the OS unbootable. Prefer building a new 7+ VM.

## Officially supported platforms

| Version | Supported RHEL-family |
|---|---|
| 19c | OL/RHEL 7.4+, 8.x |
| 18c | OL/RHEL 7.4+, 8.x |
| 12cR2 | OL/RHEL 6.8+ / 7.x |
| 11gR2 | OL/RHEL 5.x / 6.x |

CentOS / Rocky / Alma are **not officially supported** by Oracle but the binaries run. Circumvent OUI OS detection with:

```bash
export CV_ASSUME_DISTID=OL7     # use OL7/OL8 matching the major version
./runInstaller ... -ignorePrereqFailure
dbca ... -ignorePreReqs
```

Disclose the support gap to the user and record it in the plan.

## Install media layout

| Version | Media type | How to install |
|---|---|---|
| 19c / 18c / 12cR2 | Image-based zip (`LINUX.X64_193000_db_home.zip`) | Unzip the zip **directly into an empty ORACLE_HOME** as oracle. Do not unzip into a parent then move. |
| 12cR1 / 11gR2 | Traditional 2-zip media | Extract both zips into a staging dir, run `runInstaller` from stage. |

Space budget for 19c image zip: 2.9G compressed, ~6.4G uncompressed. Keep the ZIP until software install is verified, then delete it as a single file before `dbca` if space is tight.

## dbca response-file schema differences

| Aspect | 11gR2 | 12c / 18c / 19c |
|---|---|---|
| `responseFileVersion` | v11.2.0 | v12.2.0 (12cR2/18c) or v19.0.0 (19c) |
| CDB support | None | `createAsContainerDatabase=true|false`, `pdbName`, `numberOfPDBs`, `pdbAdminPassword` |
| Memory keys | `sgaTarget`, `pgaAggregateTarget`, `processes` | **`initParams=sga_target=..M,pga_aggregate_target=..M,processes=..`** + `automaticMemoryManagement=FALSE` |
| Rejects old keys? | N/A | **Yes** — `sgaTarget` etc. cause XSD `cvc-complex-type.2.4.a` failure |

This is the single most common failure: reusing 11g/12c-era memory keys in a 19c dbca response file.

## db_install.rsp differences

- Software-only install key `oracle.install.option=INSTALL_DB_SWONLY` is stable across versions.
- 12c/19c add `oracle.install.db.rootconfig.executeRootScript=false` and `oracle.installer.autoupdates.option=SKIP_UPDATES`.
- Minimal templates may omit `ORACLE_HOSTNAME`, `DECLINE_SECURITY_UPDATES`, `SECURITY_UPDATES_VIA_MYORACLESUPPORT`. If omitted, OUI may prompt for MOS credentials and hang a silent install. Append them explicitly (the generator does this).
- Group keys: `OSDBA_GROUP`, `OSOPER_GROUP`, `OSBACKUPDBA_GROUP`, `OSDGDBA_GROUP`, `OSKMDBA_GROUP`, `OSRACDBA_GROUP`. Set all DBA-family groups to `dba` for a minimal install.

## netca response file path

Found in practice:

```
$ORACLE_HOME/assistants/netca/netca.rsp
```

Not `$ORACLE_HOME/install/response/netca.rsp` on 19c. Probe both before use.

## Oracle support lifecycle caution

11gR2 and 12c are out of support. Recommend 19c (long-term support) for new test environments unless the user has a legacy compatibility requirement. Licensing is the user's responsibility; never assume an edition is licensed.
