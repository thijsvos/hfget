#!/usr/bin/env bats
#
# Online integration tests against a tiny public model (~5 MB). Disabled unless
# HFGET_RUN_NETWORK=1 so `bats tests/` stays offline-friendly by default.

TINY="sshleifer/tiny-gpt2"

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
