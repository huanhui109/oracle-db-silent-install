# Security Policy

The threat model here is narrow and specific: **a credential or a key must never
travel through an agent conversation, a command line, a log, or a generated
artifact.**

## What this project handles

| Material | Handling |
|---|---|
| SSH private keys | used implicitly by the SSH client; never read, printed, copied or fingerprinted |
| SYS / SYSTEM / PDBADMIN passwords | typed by a human into a local TTY by `fill_dbca_passwords.sh` (`read -s`); stored only in the target host's response file |
| Response files | created by generators with `__CHANGE_ME_*__` placeholders, then `chmod 600` |
| Installer output | may echo substituted values; do not `cat` a filled response file |

## Controls you can verify yourself

```bash
make test        # T30: password fill refuses a non-TTY (exit 3)
                 # T90: every password field is a placeholder, never a literal
                 # T91: no private key material anywhere in the tree
```

The interesting control is the TTY check. `fill_dbca_passwords.sh` exits 3 when
stdin is not a terminal, which makes it structurally impossible to drive it from
an agent, a pipeline, or a `ssh host 'bash -s'` stream — the only way to run it
is for a human to sit at the target's terminal.

## If a secret leaks anyway

Treat it as compromised and act in this order:

1. Rotate the password (`ALTER USER ... IDENTIFIED BY ...`) on the target.
2. Delete or overwrite the response file that held it — do not leave a `.bak`
   copy behind; the generators back up `listener.ora` but never a response file.
3. Check history: shell history, `~/.bash_history`, screen recordings,
   transcripts, CI logs.
4. If it reached this repository or a public issue, open a private security
   advisory rather than a commit that "removes it" — git history keeps it.

If a private key was displayed or transmitted: generate a new key pair, replace
the `authorized_keys` entry on every host that trusted it, and remove the old
one. Rotating the fingerprint is not enough.

## Reporting a vulnerability

Open a **private security advisory** on this repository
(Security → Report a vulnerability). Please include:

- what an attacker gains, and from what starting position;
- the exact script and invocation;
- the version and OS where you reproduced it.

Expect an initial response within a few days. There is no bug bounty.

## Out of scope

- Vulnerabilities in Oracle Database itself, in the Oracle installer, or in any
  Oracle-supplied response-file template → report to Oracle.
- The licensing or legal status of your installation.
- Misconfiguration of a production database that followed this workflow —
  the workflow targets disposable test instances, and says so repeatedly.
- Findings that require an attacker to already have root or the oracle user's
  shell on the target: at that point the database is theirs, with or without this
  repository.

## Supported versions

The `main` branch only. This is a documentation-and-script project; there are no
backports.
