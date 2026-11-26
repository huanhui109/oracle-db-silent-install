# oracle-db-silent-install

An agent skill for installing Oracle Database 11gR2 / 12c / 18c / 19c on
RHEL-family Linux — silently, repeatably, and without ever letting a password
through a chat window.

[中文说明](README.zh-CN.md) · [Installation](INSTALL.md) · [Examples](examples/) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

---

## The problem this solves

Silent Oracle installs fail in the same handful of places, and each failure
looks like something else:

| What you see | What it usually is |
|---|---|
| `cvc-complex-type.2.4.a: Invalid content ... 'memoryType'` | 11g-era memory keys fed to a 19c `dbca` response file |
| `GLIBC_2.14 not found` after a "successful" install | the OS was never able to run these binaries |
| A silent install that hangs asking for MOS credentials | the minimal template omitted `DECLINE_SECURITY_UPDATES` |
| Database reachable from the LAN on a "local test" VM | `netca` bound the listener to the FQDN, not loopback |
| An hour lost editing `/etc/hosts` that was already correct | `getent hosts` showing the IPv6 loopback alias |

Running an agent through this interactively is worse: a plausible-looking command
sequence will happily `mkdir`, `chown` and unzip before anyone has agreed on a
plan, and a password typed into a conversation is a password leaked.

This skill packages the deployment that survived that minefield — one 19c
instance on CentOS 7.9 with 3.7 GB of RAM and a loopback-only listener — as a
staged workflow with hard gates, plus the generators that make the response
files deterministic.

## The safety model

Six rules, enforced by the structure rather than by good intentions:

1. **Read-only before write.** `precheck.sh` inspects and reports; nothing is
   created, no package installed, no installer run, until a plan is approved.
2. **Root steps belong to the human.** `gen_root_prep.sh` *prints* a command
   block. The agent never runs `mkdir`/`chown`/`yum`/`sysctl -w` itself and never
   asks for a root password.
3. **Key material is never exposed.** SSH keys are used implicitly by the client;
   their contents, fingerprints and Base64 fragments never enter a log or a reply.
4. **Secrets stay on the target host.** Response files carry
   `__CHANGE_ME_SYS__` placeholders. A human fills them in a local terminal via
   `fill_dbca_passwords.sh` (`read -s`), which refuses to run without a TTY.
5. **Stage gates.** Seven stages, seven checkpoints. `dbca` does not start until
   `runInstaller` and both root scripts are verified.
6. **Cleanup is last and surgical.** After verification, delete the install zip —
   that one file. Never an `oradata` directory.

## Quick start

```bash
git clone https://github.com/huanhui109/oracle-db-silent-install.git
cd oracle-db-silent-install

# 0. look before you leap: read-only survey of the target
ssh <alias> 'bash -s -- 19c' < scripts/precheck.sh

# 1. see the whole plan, tagged by who runs what
HOST_ALIAS=<alias> VERSION=19c bash scripts/show_plan.sh 19c

# 2. generate the artifacts (no side effects beyond the named output files)
bash scripts/gen_env_file.sh - 19c
bash scripts/gen_root_prep.sh 19c > root_prep.sh
bash scripts/gen_dbca_rsp.sh /home/oracle/dbca.rsp 19c
TNS_OUT=$ORACLE_HOME/network/admin/tnsnames.ora \
  bash scripts/gen_listener_ora.sh $ORACLE_HOME/network/admin/listener.ora
```

Or let an agent drive it: point the agent at `SKILL.md` (see
[INSTALL.md](INSTALL.md)) and it will follow the same seven stages, stopping at
every checkpoint.

## How it is laid out

```
oracle-db-silent-install/
├── SKILL.md                  # the skill entry point: rules, stages, routing
├── references/               # detail loaded only when a stage needs it
│   ├── version-matrix.md     #   11g vs 12c vs 18c/19c: glibc, keys, media
│   ├── planning.md           #   directory tree, space budget, sizing, root templates
│   └── pitfalls.md           #   12 field-tested failures with exact fixes
├── scripts/                  # 9 self-contained bash scripts
├── examples/                 # two generated profiles + a full walkthrough
├── tests/                    # offline test suite (no Oracle, no network)
└── docs are at the root: INSTALL / CONTRIBUTING / SECURITY / CHANGELOG
```

`references/` exists so the agent reads 80 lines about version differences only
when it is actually choosing a version, instead of carrying the whole manual in
context.

## The seven stages

| Stage | Who runs it | Artifact |
|---|---|---|
| 0 — Preflight | agent, read-only | survey report with `BLOCKER:` lines |
| 1 — Plan and approval | agent, then human | `plan-19c.txt` |
| 2 — System preparation | **root**, human | `root_prep.sh` |
| 3 — Software install | oracle user | `db_install.rsp` → `runInstaller` |
| 4 — Root scripts | **root**, human | `orainstRoot.sh`, `root.sh` |
| 5 — Listener + database | oracle user, human types passwords | `listener.ora`, `dbca.rsp` |
| 6 — Verify and clean up | agent, read-only | `verify.sh` report |

## Scripts

Nine scripts. The ones that write, write exactly one file and say so.

| Script | Purpose | Writes |
|---|---|---|
| `precheck.sh` | Read-only readiness survey, emits `BLOCKER:`/`WARN:` verdict | nothing |
| `verify.sh` | Read-only post-install verification (instance, CDB flag, charset, memory, listener) | nothing |
| `show_plan.sh` | Prints the staged plan tagged `[AGENT]`/`[ROOT]`/`[ORACLE]` | nothing (stdout) |
| `gen_root_prep.sh` | Prints the root preparation block, derived from real RAM | nothing (stdout) |
| `gen_env_file.sh` | oracle user environment block (`ORACLE_BASE/HOME/SID/PATH/...`) | one file |
| `gen_db_install_rsp.sh` | Software-install response file from the media template | one file |
| `gen_dbca_rsp.sh` | `dbca` response file, version-correct keys, placeholder passwords | one file |
| `gen_listener_ora.sh` | Loopback `listener.ora` (+ optional `tnsnames.ora`) | one or two files |
| `fill_dbca_passwords.sh` | Interactive no-echo password fill, TTY required | edits one file |

Every script is standalone — no shared library, no `source` — so
`ssh host 'bash -s -- args' < script.sh` works. That streaming form is how the
read-only scripts reach a target without copying anything onto it.

## Version support

| Version | glibc floor | Media | `dbca` memory keys | Status |
|---|---|---|---|---|
| 19c | `GLIBC_2.14` | image zip → unpack into `ORACLE_HOME` | `initParams` | recommended |
| 18c | `GLIBC_2.14` | image zip | `initParams` | works, out of support |
| 12cR2 | `GLIBC_2.14` | image zip | `initParams` | out of support |
| 11gR2 | 2.12 is fine | two-zip, staged dir | `sgaTarget` / `pgaAggregateTarget` | out of support |

CentOS / Rocky / Alma are **not** Oracle-supported platforms. The binaries run;
`CV_ASSUME_DISTID=OL7` plus `-ignorePrereqFailure` gets past the OS check. The
skill requires the agent to say so out loud and to record it in the plan.

Details: [`references/version-matrix.md`](references/version-matrix.md).

## A real deployment, narrated

[`examples/19c-minimal-centos79/walkthrough.md`](examples/19c-minimal-centos79/walkthrough.md)
walks the seven stages with the commands, the outputs that mattered, and the two
plot twists: a glibc blocker that ended an install before it began on one VM, and
the `dbca` XSD error that cost an afternoon on another.

## Testing

```bash
make test          # or: bash tests/run_tests.sh
make lint          # bash -n everywhere, shellcheck when available
```

28 test groups (83 assertions) run offline on macOS and Linux: no Oracle, no
network, no root. They assert the contracts that matter — version-correct keys,
de-duplicated installer options, `600` on response files, exit 3 when the
password filler has no TTY, and that no generated artifact can contain a literal
password.

## Requirements

- bash 3.2+ on the machine running the generators (macOS and Linux both work)
- RedHat-family bash 4+ on the target, and root access for stages 2 and 4
- The Oracle install media, obtained by you from Oracle. Nothing here downloads
  or redistributes Oracle software.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). The short version: scripts stay
self-contained, `set -eu`, write one file, print what they wrote, and every new
behaviour gets a test. Never commit a real response file with real passwords.

## License and disclaimer

MIT — see [LICENSE](LICENSE).

Not affiliated with, endorsed by, or supported by Oracle. Oracle Database is a
trademark of Oracle Corporation. Licensing your installation is your
responsibility; this repository only encodes mechanical deployment steps.
