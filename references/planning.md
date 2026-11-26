# Planning Reference

Directory layout, space budget, memory sizing, root command templates, and security handling.

## Directory tree (parameterized)

Replace `<BASE>` with ORACLE_BASE (commonly `/u01/app/oracle`) and `<HOME>` with ORACLE_HOME.

```
/u01/
├── LINUX.X64_<ver>_db_home.zip      # install media, delete after verification
└── app/
    ├── oraInventory/                #Oracle inventory, owner oracle:oinstall
    └── oracle/
        ├── product/<ver>/db/        # ORACLE_HOME, EMPTY before unzip, owner oracle:oinstall
        ├── oradata/                 # datafiles (DBCA datafileDestination)
        └── recovery_area/           # optional FRA
```

Ownership rule: `chown -R oracle:oinstall /u01` and `chmod -R 775 /u01`, executed by root after directories are created.

## Space budget

| Item | 19c typical |
|---|---|
| ZIP compressed | 2.9 GB |
| Uncompressed ORACLE_HOME | 6.4 GB |
| non-CDB minimal datafiles | 2–4 GB |
| CDB + 1 PDB | 3–5 GB |
| Temp + redo + control | ~1 GB |
| Free headroom recommended | ≥ 3 GB |

If root partition is small (e.g. 23 GB with 18 GB free), unzip drops free space to ~8–9 GB. Delete the ZIP after software verification and before `dbca` if needed.

## Memory sizing formula

For a local test VM with physical RAM `M` MB:

```
SGA_MB    = clamp(round(M * 0.14), 512, 2048)
PGA_MB    = SGA_MB / 2
processes = 100
```

- For 3.7 GB RAM → SGA 512M, PGA 256M, processes 100 (proven working).
- For 8 GB RAM → SGA 1024M, PGA 512M.
- 19c has a practical SGA floor around 512M; below it startup may raise ORA-00838. Bump to 640M if needed.
- If the host has Swap < RAM, SGA can be pushed to swap and slow the instance; keep SGA well under physical RAM.

Also apply: `kernel.shmmax` ≈ 70–80% of physical RAM in bytes, `kernel.shmall` = shmmax / 4096. On modern kernels the defaults are often already larger than needed; adjust only if OUI warns.

## Root command templates (adapt, do not blindly paste)

Groups and user:

```bash
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
usermod -aG oinstall,dba,oper oracle    # or: usermod -g oinstall -G dba,oper oracle
id oracle
```

Directories:

```bash
mkdir -p /u01/app/oracle/product/<ver>/db
mkdir -p /u01/app/oraInventory
mkdir -p /u01/app/oracle/oradata
chown -R oracle:oinstall /u01
chmod -R 775 /u01
```

Hosts (FQDN must map to a non-loopback IP; keep localhost lines intact):

```bash
cp -p /etc/hosts /etc/hosts.bak.$(date +%F)
# append or correct: <ip> <hostname> <fqdn>
hostname -f
getent ahosts $(hostname)
ping -c 1 $(hostname)
```

Kernel parameters (`/etc/sysctl.d/99-oracle.conf`):

```
fs.aio-max-nr = 1048576
fs.file-max = 6815744
kernel.shmall = <shmmax_bytes / 4096>
kernel.shmmax = <~0.75 * physical_ram_bytes>
kernel.shmmni = 4096
kernel.sem = 800 640000 400 800
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
```

Apply with `/sbin/sysctl -p /etc/sysctl.d/99-oracle.conf` (RHEL 6/7 may not have `sysctl` in PATH).

Resource limits (`/etc/security/limits.conf`):

```
oracle   soft   nofile   1024
oracle   hard   nofile   65536
oracle   soft   nproc    2047
oracle   hard   nproc    16384
oracle   soft   stack    10240
oracle   hard   stack    32768
```

Ensure `pam_limits.so` is present in `/etc/pam.d/sshd`.

Packages (RHEL/CentOS 7):

```bash
yum install -y binutils compat-libcap1 compat-libstdc++-33 gcc gcc-c++ \
  glibc glibc-devel ksh libaio libaio-devel libgcc libstdc++ \
  libstdc++-devel libXi libXtst make sysstat elfutils-libelf-devel \
  unixODBC unixODBC-devel unzip
```

`compat-libstdc++-33` may be unavailable in minimal CentOS 7 repos. For 19c it is a warning-only prerequisite; proceed with `-ignorePrereqFailure` after telling the user.

## Listener local-only configuration

For isolated local testing, bind only to loopback. Overwrite `$ORACLE_HOME/network/admin/listener.ora`:

```
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 127.0.0.1)(PORT = 1521))
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))
    )
  )
```

Then:

```bash
lsnrctl stop; lsnrctl start
ss -lntp | grep 1521     # expect 127.0.0.1:1521 only
```

Ensure `$ORACLE_HOME/network/admin/tnsnames.ora` maps `LISTENER_ORCL` and the SID to `127.0.0.1:1521`, so `local_listener` resolves locally. Run `tnsping <SID>` to confirm.

## Security and secrets

- SSH keys: read-only. The SSH client references the key path implicitly. Never print key content, fingerprints, or Base64 in chat, logs, reports, or files. The agent must never `cat` a private or public key.
- Passwords: generated response files contain only `__CHANGE_ME_*__` placeholders. The user fills them in a local interactive terminal with `scripts/fill_dbca_passwords.sh` (uses `read -s`). Agents must not accept a password through chat, include it in a command line, or echo it.
- When capturing installer output that might contain a substituted password, pipe through a sed filter that replaces the known placeholder values with `***`, or avoid printing the response file entirely.
- Firewall: for local-only listener no firewall change is needed. If the listener must be reachable on the LAN, open 1521 explicitly with `firewall-cmd --add-port=1521/tcp --permanent && firewall-cmd --reload`.
- SELinux: permissive or disabled is acceptable for test. Avoid `setenforce 0` on systems where the user wants enforcement.

## Failure logs and rollback

| Log | Path |
|---|---|
| runInstaller | `$ORACLE_BASE/cfgtoollogs/oui/` and `/tmp/InstallActions*/installActions*.log` |
| root.sh | `$ORACLE_HOME/install/root_*.log` |
| dbca | `$ORACLE_BASE/cfgtoollogs/dbca/<SID>/<SID>.log` |
| DB alert | `$ORACLE_BASE/diag/rdbms/<SID>/<SID>/trace/alert_<SID>.log` |

Rollback red lines:
- Never `rm -rf /u01/app/oracle/oradata` unless the user explicitly confirms the database is disposable and no data is needed.
- To retry a failed `runInstaller`, clean ORACLE_HOME and oraInventory contents carefully, or use a fresh VM snapshot. Prefer a VMware snapshot taken before the install over manual cleanup.
- A failed `dbca` leaves partial files; remove only the specific `<SID>` directory under `oradata` after confirming the instance is down (`ps -ef | grep pmon`).
