# Contributing

This repository encodes a deployment that is expensive to get wrong. A
contribution is welcome when it makes the workflow **more predictable**, not when
it makes it more automated. "One script that does all seven stages" will be
declined, and the reason will be the golden rules, not taste.

## Ground rules

1. **Never weaken a gate.** No script may add a privileged operation, remove a
   checkpoint, or make a step run without confirmation.
2. **No secrets, ever.** No real password, hash, SSH key, fingerprint, hostname of
   a private machine, or customer name in code, tests, examples or issues.
3. **Scripts stay self-contained.** No `source`-ing a shared library: the
   read-only scripts are designed to run as
   `ssh host 'bash -s -- args' < script.sh`, and that only works if each file
   stands alone.
4. **Portable bash.** bash 3.2+ syntax (macOS is part of the test matrix): no
   associative arrays, no `${var,,}`, and remember that bash 3.2's builtin
   `printf` rejects a format string that begins with `-` — write
   `printf '%s\n' '--- heading ---'`.

## Script contract

Every script in `scripts/` must satisfy this list. It is what the test suite
checks, and what reviewers check first.

| Requirement | Why |
|---|---|
| `set -eu` (read-only scripts may use `set -u` only) | a silent half-run is worse than a failure |
| Exactly one output file per writer, path given as an argument | no hidden side effects |
| Fail closed with exit **2** on bad arguments, **3** when the environment cannot support the operation | callers can branch; the tests assert these codes |
| Print `GENERATED_*` / `WROTE=` receipts with effective key settings | the human reviews output, not the file |
| Never print, echo, log or interpolate a secret | the entire point of the project |
| `chmod 600` on anything that will hold a password; `644` otherwise | response files must not be world-readable |
| Header comment with usage, env overrides, and a `SAFETY CONTRACT` block | a reader must know what it touches before running it |

Current exit-code vocabulary:

| Code | Meaning |
|---|---|
| 0 | success |
| 2 | bad arguments, unknown version, missing input file/template |
| 3 | refusing to run: no TTY for interactive password entry |

## Adding a new Oracle version profile

Version differences live in four places. Adding 21c/23ai means touching all of
them, in this order:

1. `scripts/gen_env_file.sh` — the default `ORACLE_HOME` subdirectory.
2. `scripts/gen_dbca_rsp.sh` — `responseFileVersion` string, and whether memory
   goes in `initParams` or in dedicated keys.
3. `scripts/gen_db_install_rsp.sh` — any installer keys that appear or disappear.
4. `scripts/precheck.sh` — the glibc floor and the `AUTO_VERDICT` branch.

Then update `references/version-matrix.md`, `README.md`, `README.zh-CN.md`, and add
tests `t1x` mirroring the existing ones. If you cannot test against the real
media, say so in the PR — an untested version string is worse than none.

## Working on the scripts

```bash
make lint          # bash -n everywhere, shellcheck when installed
make test          # offline suite
make test FILTER=dbca   # only tests whose name contains "dbca"
make plan          # print the plan sheet (sanity-check wording)
```

Tests are plain bash in `tests/run_tests.sh`: `assert_eq`, `assert_contains`,
`assert_not_contains`, `assert_exit`, `assert_mode`. No bats, no network, no
Oracle. A new behaviour needs a new `tNN_*` function added to the `TESTS` list at
the bottom.

Two rules for tests that matter more than coverage:

- **Assert the refusal, not just the success.** A test that only proves the
  generator works will not notice if it starts leaking a password.
- **Test the artifact, not the exit code.** `test_generator_exits_0` proves very
  little; `assert_contains "$rsp" "initParams=sga_target=512M"` proves the key
  form is right for the version.

## Editing the skill text

`SKILL.md` is loaded into an agent's context. Keep it:

- **imperative** — "Run `precheck.sh`", not "the user might want to";
- **gate-first** — every stage ends in a checkpoint;
- **thin** — detail belongs in `references/`, loaded on demand. If `SKILL.md`
  grows past ~200 lines, something should move.

`references/` files are allowed to be encyclopaedic. Each one should answer a
narrow question completely: which glibc, which key, which path.

## Commits and pull requests

- One logical change per commit. Conventional-ish prefixes are welcome and used
  in this repo's history: `feat:`, `fix:`, `docs:`, `test:`, `chore:`.
- The subject says what changed for a reader of the log, not which file you
  touched.
- A PR that changes a script must state: what it wrote before, what it writes
  now, and which test proves it.
- Do not commit generated response files containing real values. The files in
  `examples/` are generated with placeholders and are safe.

## Reporting problems

- A wrong command or a missing prerequisite → open an issue with the Observed /
  Expected / Version / OS fields.
- Anything involving a leaked credential → **do not** open a public issue; see
  [SECURITY.md](SECURITY.md).
