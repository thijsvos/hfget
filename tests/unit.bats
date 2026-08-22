#!/usr/bin/env bats
#
# Offline unit tests for hfget's pure functions. These source the script (which
# skips all side effects when sourced) and call functions directly. No network.

setup() {
  HFGET="${BATS_TEST_DIRNAME}/../hfget"
  # shellcheck disable=SC1090
  source "$HFGET"
}

@test "human formats byte counts" {
  [ "$(human 0)" = "0 B" ]
  [ "$(human 999)" = "999 B" ]
  [ "$(human 1000)" = "1.0 KB" ]
  [ "$(human 1500000)" = "1.5 MB" ]
  [ "$(human 1500000000)" = "1.5 GB" ]
}

@test "normalize_model_id strips scheme, host and /tree/<rev>" {
  normalize_model_id "https://huggingface.co/Qwen/Qwen3-8B"
  [ "$NORM_MODEL" = "Qwen/Qwen3-8B" ]
  [ "$NORM_UREV" = "" ]

  normalize_model_id "hf.co/org/model/tree/dev"
  [ "$NORM_MODEL" = "org/model" ]
  [ "$NORM_UREV" = "dev" ]

  normalize_model_id "bare-model"
  [ "$NORM_MODEL" = "bare-model" ]
}

@test "MODEL_ID_RE accepts valid ids and rejects invalid ones" {
  [[ "Qwen/Qwen3-8B" =~ $MODEL_ID_RE ]]
  [[ "bare-model" =~ $MODEL_ID_RE ]]
  [[ "org/model.name_v2-1" =~ $MODEL_ID_RE ]]
  ! [[ "a/b/c" =~ $MODEL_ID_RE ]]
  ! [[ "/leading-slash" =~ $MODEL_ID_RE ]]
}

@test "matches_any performs glob matching" {
  matches_any "model-Q4_K_M.gguf" '*Q4_K_M*'
  ! matches_any "model-Q8_0.gguf" '*Q4_K_M*'
  matches_any "a/b/config.json" '*.json' '*.txt'
}

@test "parse_entry splits model and args (bash-3.2 tab-IFS regression guard)" {
  line=$(printf 'org/model\t2026-01-01T00:00:00Z\t/dest\t--verify\t-i\t*Q4*')
  parse_entry "$line"
  [ "$ENTRY_MODEL" = "org/model" ]
  [ "${#ENTRY_ARGS[@]}" -eq 4 ]
  [ "${ENTRY_ARGS[0]}" = "/dest" ]
  [ "${ENTRY_ARGS[1]}" = "--verify" ]
  [ "${ENTRY_ARGS[3]}" = "*Q4*" ]
}

@test "parse_entry handles an entry with no extra args" {
  line=$(printf 'org/model\t2026-01-01T00:00:00Z')
  parse_entry "$line"
  [ "$ENTRY_MODEL" = "org/model" ]
  [ "${#ENTRY_ARGS[@]}" -eq 0 ]
}

@test "sha256 computes the correct digest" {
  tmp="$(mktemp)"
  printf 'hello' > "$tmp"
  [ "$(sha256 "$tmp")" = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" ]
  rm -f "$tmp"
}

@test "filesize reports the byte size of a file" {
  tmp="$(mktemp)"
  printf '12345' > "$tmp"
  [ "$(filesize "$tmp")" = "5" ]
  rm -f "$tmp"
}
