#!/usr/bin/env bash
# precheck.sh - READ-ONLY Oracle Database pre-install survey.
#
# Usage (on the target Linux host, any user):
#   bash precheck.sh [VERSION]
#   VERSION: 11g | 12c | 18c | 19c   (default: 19c)
#
# Usage via an SSH alias from the controlling machine:
#   ssh <alias> 'bash -s -- 19c' < scripts/precheck.sh
#
# SAFETY CONTRACT:
#   - Read-only. No mkdir/chown/chmod/yum/sysctl -w/sed -i/unzip/install.
#   - Never reads, prints, copies or transmits SSH key material of any kind.
#   - Root-only probes are attempted and reported as N/A when permission is denied.
#
# Output sections are delimited by "=== ... ===" so they can be grepped or
# fed to a planning step. No files are created by this script.

set -u
VERSION="${1:-${ORACLE_VERSION:-19c}}"
VERSION="$(printf '%s' "$VERSION" | tr '[:upper:]' '[:lower:]')"

hr() { printf '=== %s ===\n' "$1"; }
na() { printf 'N/A (no permission)\n'; }

hr "SCRIPT_META"
printf 'version_profile=%s\n' "$VERSION"
printf 'generated_at=%s\n' "$(date '+%F %T %Z')"

hr "OS_AND_KERNEL"
cat /etc/redhat-release 2>/dev/null || grep -m1 '^PRETTY_NAME' /etc/os-release 2>/dev/null || na
printf 'uname=%s\n' "$(uname -a 2>/dev/null)"
printf 'arch=%s\n' "$(arch 2>/dev/null)"
printf 'hostname=%s\n' "$(hostname 2>/dev/null)"
printf 'hostname_f=%s\n' "$(hostname -f 2>/dev/null)"

hr "GLIBC"
ldd --version 2>&1 | head -1
printf 'glibc_rpm=%s\n' "$(rpm -q glibc 2>/dev/null || echo unknown)"
# GLIBC_2.14 is a hard requirement for Oracle 19c binaries; 11g/12c have lower floors.
if [ -r /lib64/libc.so.6 ]; then
  printf 'GLIBC_2.14_symbols=%s\n' "$(strings /lib64/libc.so.6 2>/dev/null | grep -c '^GLIBC_2.14$')"
  printf 'highest_glibc_symbol=%s\n' "$(strings /lib64/libc.so.6 2>/dev/null | grep '^GLIBC_' | sort -V | tail -1)"
fi

hr "RESOURCES"
free -m 2>/dev/null || free
printf 'cpu_cores=%s\n' "$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)"
printf '%s\n' '--- df -h ---'
df -h 2>/dev/null | grep -vE 'tmpfs|devtmpfs' | head -12
printf '%s\n' '--- df -h special ---'
df -h /dev/shm /tmp 2>/dev/null
printf '%s\n' '--- df -i ---'
df -i 2>/dev/null | head -8
printf '%s\n' '--- memory recommendation hint ---'
mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
printf 'physical_memory_mb=%s\n' "${mem_mb:-unknown}"
if [ -n "${mem_mb:-}" ]; then
  awk -v m="$mem_mb" 'BEGIN {
    sga=int(m*0.14); if (sga<512) sga=512; if (sga>2048) sga=2048
    pga=int(sga/2); pr=100
    printf "suggested_sga_mb=%d\nsuggested_pga_mb=%d\nsuggested_processes=%d\n", sga, pga, pr
  }'
fi

hr "NAME_RESOLUTION"
printf 'getent_hosts_hostname=%s\n' "$(getent hosts "$(hostname)" 2>/dev/null | head -1)"
printf 'getent_ahosts_hostname=%s\n' "$(getent ahosts "$(hostname)" 2>/dev/null | head -2 | tr '\n' ';')"
printf '%s\n' '--- /etc/hosts ---'
cat /etc/hosts 2>/dev/null
printf '%s\n' '--- nsswitch hosts line ---'
grep -E '^hosts:' /etc/nsswitch.conf 2>/dev/null
printf '%s\n' '--- ping hostname ---'
ping -c 1 -W 2 "$(hostname)" 2>&1 | head -3

hr "USERS_AND_GROUPS"
id oracle 2>&1 || printf 'oracle user MISSING\n'
for g in oinstall dba oper; do getent group "$g" 2>/dev/null || printf 'group %s MISSING\n' "$g"; done
printf '%s\n' '--- /etc/group oracle-related ---'
grep -E '^(oracle|oinstall|dba|oper):' /etc/group 2>/dev/null

hr "RPM_DEPENDENCIES"
# Core list common to 11g/12c/19c on RHEL-family systems.
packages="binutils compat-libcap1 compat-libstdc++-33 gcc gcc-c++ glibc glibc-devel ksh libaio libaio-devel libgcc libstdc++ libstdc++-devel libXi libXtst make sysstat unixODBC unixODBC-devel elfutils-libelf-devel unzip"
for p in $packages; do
  out=$(rpm -q "$p" 2>/dev/null)
  case "$out" in
    *"not installed"*) printf 'MISSING %s\n' "$p" ;;
    "") printf 'UNKNOWN %s\n' "$p" ;;
    *) printf 'OK      %s : %s\n' "$p" "$(printf '%s' "$out" | head -1)" ;;
  esac
done
printf 'preinstall_rpm=%s\n' "$(rpm -q oracle-database-preinstall-19c 2>/dev/null || echo absent)"

hr "KERNEL_PARAMETERS"
SYSCTL=/sbin/sysctl
[ -x "$SYSCTL" ] || SYSCTL=sysctl
for k in fs.aio-max-nr fs.file-max kernel.shmall kernel.shmmax kernel.shmmni kernel.sem net.ipv4.ip_local_port_range net.core.rmem_default net.core.rmem_max net.core.wmem_default net.core.wmem_max; do
  printf '%s = %s\n' "$k" "$($SYSCTL -n "$k" 2>/dev/null || echo unknown)"
done

hr "RESOURCE_LIMITS"
grep -hE '^(oracle|@oracle)' /etc/security/limits.conf /etc/security/limits.d/* 2>/dev/null || printf 'no oracle-specific limits\n'
printf '%s\n' '--- pam_limits ---'
grep -h 'pam_limits.so' /etc/pam.d/sshd /etc/pam.d/login 2>/dev/null || printf 'no pam_limits in sshd/login\n'
printf '%s\n' '--- oracle ulimit (if oracle user exists) ---'
su - oracle -c 'ulimit -a' 2>/dev/null | head -12 || na

hr "SECURITY_AND_TIME"
printf 'getenforce=%s\n' "$(getenforce 2>/dev/null || echo unknown)"
grep -E '^SELINUX=' /etc/selinux/config 2>/dev/null
printf 'firewalld=%s\n' "$(systemctl is-active firewalld 2>/dev/null || echo inactive/absent)"
printf 'iptables=%s\n' "$(service iptables status 2>/dev/null | head -1 || echo unavailable)"
printf 'date=%s\n' "$(date '+%F %T %Z')"
printf 'utc=%s\n' "$(date -u '+%F %T UTC')"
printf 'clock=%s\n' "$(cat /etc/sysconfig/clock 2>/dev/null | grep ZONE || echo unknown)"
timedatectl status 2>/dev/null | grep -E 'NTP synchronized|Time zone' || true

hr "EXISTING_ORACLE_STATE"
[ -f /etc/oratab ] && grep -vE '^\s*(#|$)' /etc/oratab || printf 'no active oratab entries\n'
printf 'listener_port_1521=%s\n' "$(netstat -an 2>/dev/null | grep -E ':1521|:1522' | head -3 || echo free)"
# Search only plausible Oracle roots: a full-filesystem scan is slow and noisy.
for root in /u01 /u02 /opt /home/oracle; do
  [ -d "$root" ] || continue
  find "$root" -maxdepth 4 -name runInstaller -type f 2>/dev/null | head -3
  find "$root" -maxdepth 4 -name oraInst.loc -type f 2>/dev/null | head -3
done

hr "ORACLE_ENV_FOR_USER_ORACLE"
if id oracle >/dev/null 2>&1; then
  su - oracle -c 'env | grep -E "^(ORACLE_BASE|ORACLE_HOME|ORACLE_SID|NLS_LANG|TMPDIR|TNS_ADMIN|LD_LIBRARY_PATH)="' 2>/dev/null || printf 'no ORACLE_* env vars\n'
  grep -E 'ORACLE|NLS_LANG|TMPDIR|TNS_ADMIN' /home/oracle/.bash_profile 2>/dev/null || printf 'no ORACLE lines in .bash_profile\n'
else
  printf 'oracle user missing\n'
fi

hr "INSTALL_ARCHIVE"
find /u01 /home/oracle /opt /tmp -maxdepth 4 -type f -iname '*db_home*.zip' -exec ls -lh {} \; 2>/dev/null || printf 'no db_home zip found in common paths\n'
printf '%s\n' '--- unzip availability ---'
command -v unzip || printf 'unzip MISSING\n'
printf '%s\n' '--- sysctl binary ---'
[ -x /sbin/sysctl ] && printf '/sbin/sysctl present\n' || printf '/sbin/sysctl MISSING (install procps-ng)\n'

hr "AUTO_VERDICT"
# Hard blockers are printed with BLOCKER prefix for easy extraction.
glibc_ok=$(strings /lib64/libc.so.6 2>/dev/null | grep -c '^GLIBC_2.14$')
case "$VERSION" in
  19c|18c|12c)
    if [ "${glibc_ok:-0}" -lt 1 ]; then
      printf 'BLOCKER: glibc lacks GLIBC_2.14 - 19c/18c/12.2+ binaries will not run. Use RHEL/OL/CentOS 7+.\n'
    else
      printf 'OK: glibc symbol requirement satisfied.\n'
    fi
    ;;
  11g)
    printf 'INFO: 11gR2 supports older glibc; verify 32-bit libs if using 32-bit bits.\n'
    ;;
esac
primary_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [ -n "$primary_ip" ] && ! getent ahosts "$(hostname)" 2>/dev/null | grep -q "$primary_ip"; then
  printf 'WARN: hostname may resolve to loopback; verify /etc/hosts maps FQDN to a non-loopback IP.\n'
fi
printf 'NOTE: getent hosts can display ::1 alias even when hostname -f and getent ahosts are correct; confirm with hostname -f and ping.\n'
printf 'NOTE: compat-libstdc++-33 is often a warning-only prerequisite for 19c; -ignorePrereqFailure can bypass it.\n'

hr "END_OF_PRECHECK"
