# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-11-26

First public release. The workflow is distilled from a real 19c deployment on
CentOS 7.9 (non-CDB single instance, SGA 512M / PGA 256M, loopback-only
listener).

### Added

- `SKILL.md` — seven-stage workflow with six non-negotiable golden rules and a
  checkpoint at every stage boundary.
- `references/version-matrix.md` — glibc floors, supported platforms, media
  layout, and response-file key differences for 11gR2 / 12c / 18c / 19c.
- `references/planning.md` — directory tree, space budget, memory sizing formula,
  root command templates, loopback listener configuration, log locations and
  rollback red lines.
- `references/pitfalls.md` — twelve field-tested failure modes with exact fixes,
  including the `dbca` XSD memory-key error and the `getent hosts` false positive.
- `scripts/precheck.sh` — read-only readiness survey emitting `BLOCKER:` and
  `WARN:` verdicts.
- `scripts/verify.sh` — read-only post-install verification of instance state,
  CDB flag, charset, memory parameters and listener binding.
- `scripts/gen_db_install_rsp.sh` — software-install response file generated from
  the media template, with the security-update keys a minimal template omits.
- `scripts/gen_dbca_rsp.sh` — version-correct `dbca` response file; passwords are
  placeholders only.
- `scripts/fill_dbca_passwords.sh` — interactive, no-echo password fill that
  refuses to run without a TTY.
- `scripts/gen_env_file.sh` — the oracle user's environment block.
- `scripts/gen_root_prep.sh` — prints (never executes) the root preparation
  block, with `kernel.shmmax`/`shmall` derived from physical RAM.
- `scripts/gen_listener_ora.sh` — loopback `listener.ora` plus an optional
  `tnsnames.ora`, warning loudly on a non-loopback bind.
- `scripts/show_plan.sh` — the review sheet, tagging every step `[AGENT]`,
  `[ROOT]` or `[ORACLE]` and numbering the checkpoints.
- `examples/19c-minimal-centos79/` — a complete generated profile plus a
  stage-by-stage walkthrough of the deployment it came from.
- `examples/11g-legacy-rhel6/` — the same shape with legacy response-file keys,
  to make the version matrix concrete.
- `tests/run_tests.sh` — 28 offline assertions covering syntax, per-version key
  forms, file modes, refusal paths and secret-handling contracts.
- `Makefile`, GitHub Actions CI (`bash -n`, shellcheck, test suite), issue and
  pull-request templates.
- `README.md` (English) and `README.zh-CN.md` (Chinese).

### Changed

- 18c is a first-class profile in every generator. The original skill text
  advertised 18c support while the generators only branched on 11g / 12c / 19c;
  the `dbca` schema string is now `v18.0.0` and 18c shares the 19c `initParams`
  form.

### Fixed

- `verify.sh` no longer aborts with an unbound-variable error when `ORACLE_HOME`
  is not exported.
- `gen_db_install_rsp.sh` and `fill_dbca_passwords.sh` no longer use `sed -i`.
  BSD sed consumes the argument after `-i` as a backup suffix, so `sed -i -E ...`
  silently edits nothing on macOS while appearing to work on GNU sed — caught by
  the macOS CI job, not locally. Both now rewrite the file through `awk`, which
  also removes the need to escape `/`, `|` and `&` in values, so a password or
  hostname containing those characters is written verbatim. `tests/run_tests.sh`
  gains `t04` to keep in-place `sed` from coming back.
- `precheck.sh` no longer scans the entire filesystem for `runInstaller`; it
  probes `/u01`, `/u02`, `/opt` and `/home/oracle` only.
- Portable `printf` usage: heading lines are emitted as
  `printf '%s\n' '--- ...'` because bash 3.2's builtin rejects a format string
  starting with `-`.
- `gen_env_file.sh` no longer leaks the caller's ambient `TMPDIR` into the
  generated profile; it uses `/tmp` unless `ORACLE_TMPDIR` is set explicitly.
- `gen_listener_ora.sh` upper-cases the SID so the emitted TNS alias follows the
  conventional `LISTENER_<SID>` form.
