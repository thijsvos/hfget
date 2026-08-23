# Contributing to hfget

Thanks for your interest! hfget is a single POSIX-friendly bash script, so
contributing is deliberately low-ceremony. By participating you agree to abide
by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ground rules

- **It stays one script.** `hfget` is a single file with no runtime dependencies
  beyond `curl`, `jq`, and standard coreutils. Please don't add a build step or
  another language.
- **bash 3.2 compatibility is required.** macOS still ships bash 3.2, so avoid
  bash 4+ features: no associative arrays, no `${var,,}`/`${var^^}`, no
  `mapfile`/`readarray`. Guard empty-array expansions as `${arr[@]+"${arr[@]}"}`.
- **Portable commands only.** Prefer POSIX flags. Where BSD (macOS) and GNU
  (Linux) differ (`stat`, `sha256sum`/`shasum`, `date`), use a fallback helper —
  see `filesize`, `sha256`, and `file_birth` for the pattern (GNU first).

## Before opening a PR

```sh
shellcheck hfget            # must be clean
bats tests/unit.bats        # offline unit tests
HFGET_RUN_NETWORK=1 bats tests/integration.bats   # optional: hits huggingface.co
```

Install the tools with `apt install shellcheck bats jq`,
`dnf install ShellCheck bats jq`, or `brew install shellcheck bats-core jq`.

CI runs shellcheck plus the unit tests on Linux and macOS, and the integration
tests on Linux. Please add or update tests when you change behavior.

## Style

- Keep functions small and single-purpose; the script is organized as shared
  helpers → `cmd_download` → queue machinery → dispatch.
- Bump `VERSION` in `hfget` and add a `CHANGELOG.md` entry for user-visible
  changes.
