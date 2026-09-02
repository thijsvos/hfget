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
code and runs nothing it downloads.

## What hfget does about the content of a model

Model files can carry code: pickle-based formats (`.bin`, `.pt`, `.pth`,
`.ckpt`, `.pkl`) execute it when a program loads them. hfget cannot make such a
file safe, but it makes sure you know what you are about to trust:

- Before every `download`, `add` and `update` it queries HuggingFace's
  malware/pickle scanners for the repo and **refuses flagged files** (exit code
  `2`) unless `--allow-unsafe` is given. This is a gate on the Hub's verdict,
  not an independent scan: files the Hub has not scanned yet, or that evade
  its scanners, pass with a "not yet scanned"/format warning.
- `hfget scan` shows per-file verdicts and the dangerous pickle imports the
  scanners found; `hfget audit` re-checks everything on disk and identifies
  formats by their bytes, so a pickle hiding behind a `.safetensors` name is
  reported.
- Verdicts are recorded in the manifest, and `update` reports a repo that was
  clear when fetched but is flagged now.

Review any model you download before loading it in your own tooling, and
prefer `.safetensors`/`.gguf` over pickle-based files whenever the author
offers them.
