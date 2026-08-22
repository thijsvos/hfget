# Security Policy

## Reporting a vulnerability

Please report security issues privately using GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
("Report a vulnerability" on the Security tab) rather than opening a public
issue. You can expect an initial response within a few days.

## How hfget handles your token

- Your HuggingFace token is read from `-t`/`--token`, `$HF_TOKEN`, or the
  official CLI token files (`~/.cache/huggingface/token`, `~/.huggingface/token`).
- It is written to a temporary header file created with `600` permissions and
  passed to `curl` via `-H @file`, so it never appears on curl's command line.
- The temp directory is removed on exit. The token is **not** written to the
  queue state — `hfget add -t <token>` strips it before saving, and the
  background runner re-resolves it from `$HF_TOKEN`/the token file at run time.
- **Prefer `$HF_TOKEN` or a token file over `-t`.** A value passed as `-t` is
  visible in your own process list (`ps`) and shell history while the command
  runs; `$HF_TOKEN`/the token file avoid that. For gated models via the queue,
  use `$HF_TOKEN`/the token file so the runner can authenticate.

## Scope

hfget downloads files from `huggingface.co` over HTTPS. It executes no model
code and runs nothing it downloads. Review any model you download before using
it in your own tooling.
