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
  passed to `curl` via `-H @file`, so it never appears in the process list
  (`ps`) or in shell history.
- The temp directory is removed on exit. The token is never logged or written to
  the queue state.

## Scope

hfget downloads files from `huggingface.co` over HTTPS. It executes no model
code and runs nothing it downloads. Review any model you download before using
it in your own tooling.
