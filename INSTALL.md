# Installation

Two ways to use this project: as an **agent skill** (the workflow, gates and
references come along automatically), or as a **plain shell toolbox** (you drive,
the scripts generate).

---

## Option A — as an agent skill

A skill is a directory whose `SKILL.md` carries a `name` and a `description` in
its YAML frontmatter. The client reads the description at startup and loads the
body only when a request matches it. The directory name must match `name`.

### Claude Code

Personal (available in every project):

```bash
git clone https://github.com/huanhui109/oracle-db-silent-install.git \
  ~/.claude/skills/oracle-db-silent-install
```

Project-scoped (committed with your repo, shared with collaborators):

```bash
mkdir -p .claude/skills
git clone https://github.com/huanhui109/oracle-db-silent-install.git \
  .claude/skills/oracle-db-silent-install
```

### WorkBuddy

```bash
git clone https://github.com/huanhui109/oracle-db-silent-install.git \
  ~/.workbuddy/skills/oracle-db-silent-install
```

### Any other client that reads SKILL.md

Copy or clone the directory into whatever path that client scans for skills.
Nothing in the repository assumes a particular client — `SKILL.md`,
`references/` and `scripts/` are plain files.

If your client has no skill mechanism at all, use Option B, or hand `SKILL.md`
to the agent as a document and tell it to follow the stages.

### Or via make

```bash
make install-skill DEST=~/.claude/skills
make install-skill DEST=~/.workbuddy/skills
```

### Checklist after installing

1. The directory name equals the `name:` in `SKILL.md` —
   `oracle-db-silent-install`.
2. `scripts/*.sh` are executable (`ls -l scripts/`).
3. Restart or reload the client so it re-scans the skills directory.
4. Ask something in the skill's trigger range, e.g.
   *"install Oracle 19c silently on a CentOS 7 VM over SSH"*. The skill should
   announce itself and start with a read-only preflight — never with `mkdir`.
5. If it starts executing privileged commands without a plan, stop it and check
   that it actually loaded `SKILL.md` rather than improvising.

---

## Option B — as a shell toolbox

No installation. Clone anywhere and run the scripts:

```bash
git clone https://github.com/huanhui109/oracle-db-silent-install.git
cd oracle-db-silent-install

bash scripts/precheck.sh 19c                       # on the target, read-only
bash scripts/show_plan.sh 19c                      # print the plan
bash scripts/gen_dbca_rsp.sh /home/oracle/dbca.rsp 19c
```

Every script prints its own usage if you pass no arguments where arguments are
required. `bash scripts/<name>.sh` with a missing required argument exits 2.

---

## Requirements

| Where | Needs |
|---|---|
| Machine running the generators | bash 3.2+ (macOS, Linux), `sed`, `awk` |
| Target host | RHEL / OL / CentOS / Rocky / Alma, bash 4+, `unzip`, `strings` |
| Target host, stage 2 and 4 | root access — executed by a human, not by the agent |
| Target host, stage 3 and 5 | the `oracle` user, with the install media already staged |
| Oracle install media | obtained by you from Oracle; not included or downloaded here |

Optional, for development: `shellcheck` (lint) — everything else is stdlib bash.

## Verifying the checkout

```bash
make test      # 28 offline assertions, no Oracle and no network needed
make lint      # bash -n on every script + shellcheck when available
```

If `make test` passes, the generators behave as documented on your machine.

## Upgrading

```bash
cd <the skill directory> && git pull --ff-only
```

Response files you generated earlier stay valid; only regenerate the ones whose
generator changed. `CHANGELOG.md` says which.

## Uninstalling

Delete the skill directory. The scripts write nothing outside the output paths
you pass them, so there is no state to clean up on the target host — except the
response files you created yourself.
