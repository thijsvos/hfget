# hfget

[![CI](https://github.com/thijsvos/hfget/actions/workflows/ci.yml/badge.svg)](https://github.com/thijsvos/hfget/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-14b8a6.svg)](LICENSE)
![Platform: macOS · Linux](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Linux-555.svg)

Download HuggingFace models to any directory — a local disk, an external drive,
or a mounted NAS share — with a **built-in download queue**. One bash script,
no Python, no build step. It just needs `curl` and `jq`.

![hfget in action: download a model, see where it's stored, then queue more](demo.gif)

...and for a whole set, queue them and watch the live progress:

```console
$ hfget download Qwen/Qwen3-8B ~/models
$ hfget add Qwen/Qwen3-8B mistralai/Mistral-7B-Instruct-v0.3   # queue several, walk away
$ hfget queue                                                  # live progress bar
runner:  active (pid 4211)
current: ▶ Qwen/Qwen3-8B — 2m13s
         ↓ model-00002-of-00004.safetensors
         [██████████░░░░░░░░░░░░░░] 43%  7.1 GB / 16.4 GB  ~4m20s left
pending:
   1. mistralai/Mistral-7B-Instruct-v0.3
```

## Features

- **Straight to disk** — files stream directly into the destination, nothing is
  cached under `~`. Point it at a huge drive from a small laptop.
- **A real queue** — enqueue N models; a background runner downloads them one at
  a time and picks up anything you add mid-run. Watch a live progress bar with
  percent, bytes and ETA (`hfget queue`).
- **Smart updates** — `hfget update` re-fetches only the files that actually
  changed upstream (compared by content hash, not just size), leaves unchanged
  multi-GB weights in place, and cleans up files removed upstream. `hfget
  outdated` shows which of your saved models have a new version.
- **Resumable & verifiable** — interrupted downloads resume at the byte offset;
  `--verify` sha256-checks large files against HuggingFace's published hashes.
- **No surprises** — before downloading it shows a size + contents breakdown and
  asks for confirmation; huge or multi-quant (GGUF) repos default to *No*.
- **Glob filters** — grab just one GGUF quant or skip duplicate weight formats
  with `--include`/`--exclude`.
- **Gated-model aware** — detects gated/private repos up front with clear
  license/token instructions instead of failing halfway.
- **Won't fetch what HuggingFace's scanners flagged** — before every download,
  queue entry and update, hfget asks the Hub's malware/pickle scanners about the
  repo and refuses flagged files (`--allow-unsafe` overrides). `hfget scan`
  shows per-file verdicts and formats before you commit; `hfget audit` lists
  everything on your disk, what format it really is, and whether it is still
  clear.
- **Cross-platform** — macOS and Linux, bash 3.2+.

## Requirements

- `bash` 3.2 or newer
- `curl` and `jq`
- Standard coreutils (`awk`, `sed`, `grep`, `stat`, `df`, …) — present on macOS
  and every Linux
- `sha256sum` or `shasum` — only for `--verify`

Install jq if you don't have it: `sudo apt install jq` / `sudo dnf install jq` /
`brew install jq`.

## Install

One line (installs the latest release to `/usr/local/bin` or `~/.local/bin`):

```sh
curl -fsSL https://raw.githubusercontent.com/thijsvos/hfget/main/install.sh | sh
```

As with any `curl | sh`, it's healthy to read what you run first — open
[`install.sh`](install.sh) (it just downloads the latest release of the single
`hfget` script), or use the clone-and-inspect path below.

Or clone / copy the single file:

```sh
git clone https://github.com/thijsvos/hfget.git
cd hfget && chmod +x hfget
ln -s "$PWD/hfget" /usr/local/bin/hfget      # or ~/.local/bin/hfget
```

There's nothing else to install — it's one bash script.

**Supported:** macOS and Linux, `bash` 3.2+, with `curl` and `jq`. (Windows
only via WSL. Not on Homebrew — install with the one-liner above.)

Set a default download directory once (optional):

```sh
export HFGET_DEST="$HOME/models"      # add to ~/.zshrc or ~/.bashrc
```

## Quickstart

```sh
hfget download Qwen/Qwen3-8B ~/models          # download now, to ~/models/Qwen/Qwen3-8B
hfget download Qwen/Qwen3-8B                    # uses $HFGET_DEST
hfget download bartowski/Some-Model-GGUF --list # peek at files + sizes first
hfget download meta-llama/Llama-3.1-8B-Instruct --verify -t hf_xxx   # gated + checksum
```

Pasted URLs work too: `hfget download https://huggingface.co/Qwen/Qwen3-8B`.

## The queue

```sh
hfget add <model...> [options]   # enqueue (+ auto-start the background runner; --no-start to skip)
hfget queue [seconds]            # LIVE watch (default refresh: 1s); Ctrl-C to exit
hfget status                     # one-shot snapshot (good for scripts)
hfget rm <n|model>               # remove a pending entry (by id: also a failed one)
hfget clear [--all|--failed]     # drop pending; --failed dismisses failures; --all wipes everything + stops runner
hfget retry                      # re-queue failed entries
hfget stop [--now]               # stop after current model / immediately (resumable)
hfget run                        # process the queue in the foreground
hfget log [model]                # tail the current (or named) download log
```

`add` is all you normally touch: it enqueues, checks each model against the API
first (size, contents, gated status), and silently starts a background runner.
Trailing options are stored **per entry**, so each model can have its own
filters:

```sh
hfget add bartowski/Llama-3.3-70B-Instruct-GGUF -i '*Q4_K_M*'   # one quant only
hfget add Qwen/Qwen3-8B --verify
```

Everything is resumable: kill the runner, reboot, or `hfget stop` — rerunning
picks up where it left off. State lives in `~/.hfget/` (or `$XDG_STATE_HOME/hfget`).

## Keeping models up to date

Model authors push new revisions — retrained weights, a fixed tokenizer, added
or removed files. `hfget update` refreshes a local copy the smart way: it diffs
the repo against what you already have and **re-downloads only what changed**,
leaving untouched multi-GB weights exactly where they are (no delete-and-replace).

```sh
hfget update Qwen/Qwen3-8B ~/models     # re-fetch only changed/new files
hfget update --all ~/models             # refresh every saved model in one pass
hfget outdated ~/models                 # just report which have updates
```

Each download records a tiny manifest inside the model folder
(`.hfget/manifest.tsv`) with the content hash and revision of every file. An
update compares that against the repo's current hashes, so even a file whose
**size didn't change** but whose contents did is caught — and nothing is re-read
off your disk (or NAS) to find out. The manifest travels with the data, so a
second machine reading the same share gets exact, cheap updates too.

Files **removed upstream** are listed and, once you confirm, deleted — only files
hfget itself recorded downloading, never anything you added. Change the default:

| Flag | What happens to files removed upstream |
|---|---|
| *(default)* | list them and ask; they're kept unless you say yes |
| `--prune` | remove them without asking |
| `--keep` | never remove — only add and replace |
| `--backup` | move them to `<dest>/.hfget-old/<date>/` instead of deleting |

**Partial downloads stay partial.** If you only kept one file of a repo — most
often a single GGUF quant out of many — hfget remembers the `-i`/`-x` filter you
downloaded with and re-applies it on every `update` (and `update --all`), so it
never balloons into the whole repo. Pass `-i`/`-x` again only when you want to
*change* what you keep.

Other options mirror `download` (`-r`, `-i`/`-x`, `-t`, `-j`, `--verify`).
`--rehash` hashes local files to detect same-size changes exactly on the first
update of a folder that predates manifests. Set `HFGET_NO_MANIFEST=1` to skip
writing the manifest (updates then fall back to size-only comparison, and
pruning is disabled for safety).

## Is it safe to load?

A model file is not just bytes: **pickle-based formats** (`.bin`, `.pt`, `.pth`,
`.ckpt`, `.pkl`) execute code when a program loads them, and HuggingFace runs
malware and pickle scanners over every repo — but the Hub only *marks* a file
`unsafe`; it never stops you (or a downloader) from fetching it. hfget acts on
those verdicts:

- **Every fetch is gated.** `download`, `add` and `update` ask the Hub's scanners
  about the repo first (one small API call) and refuse to fetch flagged files —
  exit code `2`, and nothing is created on disk. `add` rejects such a model
  instead of queueing it, the same way it rejects gated repos. Pass
  `--allow-unsafe` if you understand the risk and want it anyway.
- **The verdict travels with the data.** The manifest records it, and `update`
  re-checks: a repo that turned bad *after* you first fetched it — or a file the
  scanners only later learned to flag — is reported as *"was clear when you
  fetched it on …"*.
- **Plain-English format notes.** Pre-flight tells you when the selection
  contains files that can run code, and suggests `.safetensors`/`.gguf` when the
  author offers them.

```sh
hfget scan InstantX/InstantID           # per-file: size, format, verdict, dangerous pickle imports
hfget audit ~/models                    # everything on disk: size, fetched when, filter, formats, verdict
hfget audit ~/models --offline          # same, from what was recorded at fetch time (no network)
```

`audit` classifies files by their **bytes**, not their names — a file called
`model.safetensors` whose content is a pickle is reported as a *hidden pickle*.
Both commands exit `2` when anything is flagged, so they work in scripts. Set
`HFGET_SCAN=off` to skip the scanner check entirely (e.g. an offline mirror).

hfget itself never runs anything it downloads; these checks tell you what you
are about to trust before another program loads it.

## Why hfget?

The official `hf` CLI and other downloaders work well, but hfget fills a
specific niche:

| | hfget | `hf` CLI | hfd.sh | HF Model Downloader |
|---|:---:|:---:|:---:|:---:|
| Dependencies | curl + jq | Python | curl/aria2 | Go binary |
| Built-in queue | ✅ | — | — | — |
| Live progress + ETA | ✅ | partial | ✅ | ✅ |
| Straight to any dir, no cache | ✅ | needs flags | ✅ | ✅ |
| Size/quant confirmation | ✅ | — | — | partial |
| Incremental update + prune | ✅ | partial | — | — |
| Refuses scanner-flagged files; audits what's on disk | ✅ | — | — | — |
| Resumable | ✅ | ✅ | ✅ | ✅ |

If you want to line up a dozen models and let them trickle onto a NAS or big
drive overnight, the queue is the reason to use hfget.

## Gated models (Llama, Gemma, …)

1. Accept the license on the model's HuggingFace page.
2. Create a read token at <https://huggingface.co/settings/tokens>.
3. `export HF_TOKEN=hf_…` (or pass `-t hf_…`). A token saved by the official CLI
   (`~/.cache/huggingface/token`) is picked up automatically.

The token is passed to curl via a `600`-permission header file, so it never
shows up in `ps`.

## Environment variables

| Variable | Purpose |
|---|---|
| `HFGET_DEST` | default download dir (legacy alias: `HF_NAS_DIR`) |
| `HF_TOKEN` | access token for gated/private models |
| `HF_HOME` | where the official CLI keeps its token file (`$HF_HOME/token`, default `~/.cache/huggingface`) — read when `HF_TOKEN` is unset |
| `HFGET_STATE_DIR` | queue state dir (default: `$XDG_STATE_HOME/hfget` or `~/.hfget`) |
| `HFGET_WARN_GB` | size (GB) above which confirmation defaults to No (default 100) |
| `HFGET_YES` | skip confirmation prompts (same as `-y`) |
| `HFGET_MIN_SPEED` | reconnect if a transfer stalls below this many bytes/sec (default 1 MB/s; `0` disables) |
| `HFGET_SPEED_TIME` | seconds a stall must persist before reconnecting (default 30) |
| `HFGET_QUEUE_NOSTART` | `add` never auto-starts the background runner |
| `HFGET_QUEUE_NOWAIT` | the runner doesn't wait for a manual download in progress |
| `HFGET_NOCAFFEINE` | don't keep the machine awake (macOS) |
| `HFGET_NO_MANIFEST` | don't write the per-model `.hfget/manifest.tsv` (update/outdated fall back to size-only) |
| `HFGET_SCAN` | `off` skips the HuggingFace scanner check before fetching (default: on) |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | error, aborted at a confirmation prompt, or (`update`) any model failed or was refused |
| `2` | refused by HuggingFace's scanners: a file to fetch is flagged (`download`), or something is flagged (`scan`/`audit`; `audit` also for a hidden pickle) |
| `130` | interrupted (Ctrl-C) — partial files are kept and resume |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `jq is required` | Install jq (`apt`/`dnf`/`brew`). |
| Download refused with `--require-mount` | The destination isn't a network mount; drop the flag for a local dir. |
| Warning about `/Volumes/... resolves to the local disk` (macOS) | The NAS share isn't mounted; mount it first, or you'll fill the local disk. |
| `HTTP 401/403` | Gated/private repo — accept the license and supply a token. |
| `refusing to download … flagged by HuggingFace's malware/pickle scanners` | The Hub flagged a file in that repo. See `hfget scan <model>`; exclude the file (`-x`), pick a `.safetensors` variant, or, if you accept the risk, add `--allow-unsafe`. |
| `Operation not permitted` on a network volume (macOS) | Grant your terminal access to network volumes in System Settings → Privacy & Security → Files and Folders. |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: keep it one portable bash 3.2
script, run `shellcheck hfget` and `bats tests/unit.bats`, and add tests for
behavior changes.

## License

[MIT](LICENSE).
