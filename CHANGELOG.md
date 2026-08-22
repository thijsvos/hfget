# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project uses the
`VERSION` string in the `hfget` script as the source of truth.

## [2.5.0] — 2026-08-23

### Added
- **Self-healing transfers.** If a download stalls below `HFGET_MIN_SPEED`
  bytes/sec (default 1 MB/s) for `HFGET_SPEED_TIME` seconds (default 30), curl
  aborts and hfget reconnects, resuming from the `.part`. Previously the abort
  floor was 1 KB/s, so a connection degraded to a fraction of the achievable
  rate could crawl for hours without recovering.
- The retry loop is now **progress-aware**: a reconnect that keeps moving bytes
  forward is never counted as a failure; hfget only gives up after 3 attempts
  that make no progress at all. Set `HFGET_MIN_SPEED=0` to disable (slow links).

## [2.4.0] — 2026-08-22

### Changed
- **Cross-platform: now runs on Linux as well as macOS.** `filesize()` now tries
  GNU `stat` before BSD `stat` (the previous order returned bogus values on
  Linux and corrupted resume/skip/size logic).
- **Any destination is allowed by default.** The network-mount requirement is
  now opt-in via `--require-mount`; `--force-local` is accepted as a no-op for
  compatibility. The macOS `/Volumes` unmounted-share trap is now a warning.
- Destination env var is now `HFGET_DEST` (`HF_NAS_DIR` still honored).
- State dir honors `XDG_STATE_HOME` when set.

### Added
- Portable `sha256` helper (`sha256sum` or `shasum`); `--verify` degrades to a
  warning instead of failing when neither tool is present.
- Portable `file_birth` helper for the queue watcher's elapsed/ETA display.
- The script can be `source`d without side effects (for the test suite).
- Test suite (bats): offline unit tests + network-gated integration tests.
- GitHub Actions CI: shellcheck + unit tests on Linux and macOS, integration
  tests on Linux.

### Fixed
- `ps -axww` so the queue's "polite wait" detection isn't truncated on Linux.
- OS-aware dependency hint for missing `jq`.

## [2.3.0] — 2026-08-22

### Added
- Live progress bar in `hfget queue`/`status` with exact percentage, bytes and
  ETA, fed by a local progress file so the watcher never stalls on the NAS.

## [2.2.x] — 2026-08-22

### Added
- `hfget clear --all` to wipe the whole queue (pending + failed + current) and
  stop the runner.
- Size/contents overview and a confirmation prompt before downloading or
  queueing; large or multi-quant GGUF selections default the prompt to No.
- `add` pre-checks each model (listing + auth probe) so gated models are caught
  at queue time; the destination is resolved and stored per entry.

### Fixed
- Destination directory is created only after all pre-flight checks pass (a
  gated/dry-run download leaves nothing behind).

## [2.1.0] — 2026-08-22

### Added
- `hfget queue [sec]` live watcher (configurable refresh, default 1s);
  `hfget status` one-shot snapshot.

### Changed
- Subcommands are required; the bare `hfget <model>` form was removed in favor
  of `hfget download <model>`.

## [2.0.0] — 2026-08-22

### Added
- Built-in download queue: `add`, `queue`, `run`, `stop`, `rm`, `clear`,
  `retry`, `log`, with an auto-started background runner, crash recovery, and
  resumable stops.

## [1.0.0] — 2026-08-21

### Added
- Initial release: resumable, verifiable HuggingFace model downloads straight to
  a directory, with glob filters, `--list`/`--dry-run`, and token support.
