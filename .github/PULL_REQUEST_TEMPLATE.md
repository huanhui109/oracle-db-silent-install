## What this changes

<!-- One paragraph. What did the workflow do before, what does it do now? -->

## Which stage / script

<!-- e.g. Stage 5, scripts/gen_dbca_rsp.sh -->

## Proof

<!--
A test is the proof. Quote the assertion you added and paste the relevant part of
`bash tests/run_tests.sh` output.
-->

```
$ bash tests/run_tests.sh
...
```

## Checklist

- [ ] `make lint` passes (`bash -n` on every script; ShellCheck clean where available)
- [ ] `make test` passes, and new behaviour has a new `tNN_*` test
- [ ] Scripts remain standalone (no `source`, no shared library)
- [ ] No privileged command was added that runs without human confirmation
- [ ] No secret, hostname, IP, username or key material in code, tests, examples or this description
- [ ] `CHANGELOG.md` updated under `## [Unreleased]`
- [ ] If a version profile changed: `references/version-matrix.md`, `README.md` and `README.zh-CN.md` updated together
