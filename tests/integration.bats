#!/usr/bin/env bats
#
# Online integration tests against a tiny public model (~5 MB). Disabled unless
# HFGET_RUN_NETWORK=1 so `bats tests/` stays offline-friendly by default.

TINY="sshleifer/tiny-gpt2"
# A well-known demonstration of a malicious pickle, flagged "unsafe" by the
# Hub's scanners. Only ever used to assert that hfget REFUSES it (dry-run);
# nothing from it is downloaded or executed.
FLAGGED="ykilcher/totally-harmless-model"

setup() {
  HFGET="${BATS_TEST_DIRNAME}/../hfget"
  if [ "${HFGET_RUN_NETWORK:-0}" != "1" ]; then
    skip "network tests disabled (set HFGET_RUN_NETWORK=1 to enable)"
  fi
  DEST="$(mktemp -d)"
  STATE="$(mktemp -d)"
  export HFGET_NOCAFFEINE=1 HFGET_STATE_DIR="$STATE"
}

teardown() {
  [ -n "${DEST:-}" ] && rm -rf "$DEST"
  [ -n "${STATE:-}" ] && rm -rf "$STATE"
}

@test "download to a local dir with no NAS flags" {
  run "$HFGET" download "$TINY" "$DEST" -y
  [ "$status" -eq 0 ]
  [ -f "$DEST/$TINY/config.json" ]
}

@test "re-running skips already-complete files" {
  "$HFGET" download "$TINY" "$DEST" -y
  run "$HFGET" download "$TINY" "$DEST" -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
}

@test "--list shows files without downloading" {
  run "$HFGET" download "$TINY" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"config.json"* ]]
}

@test "--dry-run reports without writing anything" {
  run "$HFGET" download "$TINY" "$DEST" --dry-run
  [ "$status" -eq 0 ]
  [ ! -d "$DEST/$TINY" ]
}

@test "--verify downloads and checksums LFS files" {
  run "$HFGET" download "$TINY" "$DEST" --verify -y
  [ "$status" -eq 0 ]
  [ -f "$DEST/$TINY/config.json" ]
}

@test "--include filters the file set" {
  run "$HFGET" download "$TINY" "$DEST" -i '*.json' -y
  [ "$status" -eq 0 ]
  [ -f "$DEST/$TINY/config.json" ]
  [ ! -f "$DEST/$TINY/pytorch_model.bin" ]
}

@test "queue add then run drains to the destination" {
  export HFGET_QUEUE_NOSTART=1 HFGET_QUEUE_NOWAIT=1
  run "$HFGET" add "$TINY" "$DEST" -y
  [ "$status" -eq 0 ]
  run "$HFGET" run
  [ "$status" -eq 0 ]
  [ -f "$DEST/$TINY/config.json" ]
}

# ---------------------------------------------------------------- update ----

@test "download seeds a manifest, and update reports up to date" {
  "$HFGET" download "$TINY" "$DEST" -y
  [ -f "$DEST/$TINY/.hfget/manifest.tsv" ]
  grep -q 'commit=[0-9a-f]' "$DEST/$TINY/.hfget/manifest.tsv"
  run "$HFGET" update "$TINY" "$DEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "update re-fetches only a changed file and leaves the rest untouched" {
  "$HFGET" download "$TINY" "$DEST" -y
  mf="$DEST/$TINY/.hfget/manifest.tsv"
  before="$(stat -f %m "$DEST/$TINY/config.json" 2>/dev/null || stat -c %Y "$DEST/$TINY/config.json")"
  # tamper the recorded hash for one LFS file so it looks changed upstream
  awk -F'\t' 'BEGIN{OFS="\t"} $1=="pytorch_model.bin"{$3="deadbeef"} {print}' "$mf" > "$mf.t" && mv "$mf.t" "$mf"
  run "$HFGET" update "$TINY" "$DEST" -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed:       1"* ]]
  after="$(stat -f %m "$DEST/$TINY/config.json" 2>/dev/null || stat -c %Y "$DEST/$TINY/config.json")"
  [ "$before" = "$after" ]        # unrelated file not rewritten
}

@test "stale file: default keeps it, --prune removes it" {
  "$HFGET" download "$TINY" "$DEST" -y
  mf="$DEST/$TINY/.hfget/manifest.tsv"
  printf 'STALE' > "$DEST/$TINY/removed_upstream.bin"
  printf 'removed_upstream.bin\t5\t-\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' >> "$mf"
  # non-interactive default is No -> kept
  "$HFGET" update "$TINY" "$DEST"
  [ -f "$DEST/$TINY/removed_upstream.bin" ]
  # --prune removes it
  "$HFGET" update "$TINY" "$DEST" --prune
  [ ! -f "$DEST/$TINY/removed_upstream.bin" ]
}

@test "update --dry-run does not write a manifest" {
  "$HFGET" download "$TINY" "$DEST" -y
  rm -rf "$DEST/$TINY/.hfget"
  run "$HFGET" update "$TINY" "$DEST" --dry-run
  [ "$status" -eq 0 ]
  [ ! -d "$DEST/$TINY/.hfget" ]     # dry-run must change nothing on disk
}

@test "outdated reports up to date, and flags a tampered commit" {
  "$HFGET" download "$TINY" "$DEST" -y
  run "$HFGET" outdated "$DEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
  mf="$DEST/$TINY/.hfget/manifest.tsv"
  sed 's/commit=[0-9a-f]*/commit=0000000000000000000000000000000000000000/' "$mf" > "$mf.t" && mv "$mf.t" "$mf"
  run "$HFGET" outdated "$DEST"
  [[ "$output" == *"update available"* ]]
}

@test "update inherits an exclude-only recorded filter without crashing (bash 3.2 set -u guard)" {
  "$HFGET" download "$TINY" "$DEST" -x '*.h5' -y
  grep -q $'^# exclude\t\\*.h5$' "$DEST/$TINY/.hfget/manifest.tsv"
  run "$HFGET" update "$TINY" "$DEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"keeping this model's recorded filter"* ]]
}

# ---------------------------------------------------------------- safety ----

@test "scan lists per-file verdicts and formats for a clean repo (exit 0)" {
  run "$HFGET" scan "$TINY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pytorch_model.bin"* ]]
  [[ "$output" == *"pickle"* ]]
  [[ "$output" == *"9 files:"* ]]
}

@test "scan exits 2 and names the flagged file for a repo the scanners flagged" {
  run "$HFGET" scan "$FLAGGED"
  [ "$status" -eq 2 ]
  [[ "$output" == *"FLAGGED:unsafe"*"pytorch_model.bin"* ]]
}

@test "download refuses a flagged repo before touching the disk; --allow-unsafe overrides" {
  run "$HFGET" download "$FLAGGED" "$DEST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"refusing to download"* ]]
  [ ! -d "$DEST/ykilcher" ]
  run "$HFGET" download "$FLAGGED" "$DEST" --dry-run --allow-unsafe
  [ "$status" -eq 0 ]
  [[ "$output" == *"--allow-unsafe given"* ]]
  # excluding the flagged file makes the rest of the repo fetchable
  run "$HFGET" download "$FLAGGED" "$DEST" --dry-run -x 'pytorch_model.bin'
  [ "$status" -eq 0 ]
  [[ "$output" == *"not among the files to fetch"* ]]
}

@test "--list marks flagged files with !" {
  run "$HFGET" download "$FLAGGED" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"! pytorch_model.bin"* ]]
}

@test "add rejects a flagged repo instead of queueing it" {
  export HFGET_QUEUE_NOSTART=1
  run "$HFGET" add "$FLAGGED" "$DEST" -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"refusing to queue"* ]]
  [ ! -s "$STATE/queue.tsv" ]
}

@test "download records the scanner verdict in the manifest, and audit reads the archive" {
  "$HFGET" download "$TINY" "$DEST" -y
  grep -q ' scan=' "$DEST/$TINY/.hfget/manifest.tsv"
  run "$HFGET" audit "$DEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TINY"* ]]
  [[ "$output" == *"pickle"* ]]
  [[ "$output" == *"1 model(s)"* ]]
}
