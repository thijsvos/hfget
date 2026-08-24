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

@test "assert_safe_paths rejects traversal and absolute paths, allows normal ones" {
  bad="$(mktemp)"
  printf '10\t-\t../../etc/passwd\n' > "$bad"
  run bash -c "source '$HFGET'; MODEL=x/y; assert_safe_paths '$bad'"
  [ "$status" -ne 0 ]
  printf '10\t-\t/etc/passwd\n' > "$bad"
  run bash -c "source '$HFGET'; MODEL=x/y; assert_safe_paths '$bad'"
  [ "$status" -ne 0 ]
  printf '10\t-\ta/b/..\n' > "$bad"
  run bash -c "source '$HFGET'; MODEL=x/y; assert_safe_paths '$bad'"
  [ "$status" -ne 0 ]
  printf '10\t-\tsubdir/model file.safetensors\n' > "$bad"
  run bash -c "source '$HFGET'; MODEL=x/y; assert_safe_paths '$bad'"
  [ "$status" -eq 0 ]
  rm -f "$bad"
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

# ---------------------------------------------------------------- update ----

@test "build_tree4 joins sizes with git/lfs oids by path" {
  TMPD="$(mktemp -d)"
  FILES_TSV="$TMPD/files"; OIDS_TSV="$TMPD/oids"
  printf '100\tshaA\tfileA\n' >  "$FILES_TSV"
  printf '5\t-\tfileB\n'      >> "$FILES_TSV"
  printf 'fileA\tgitA\tshaA\n' >  "$OIDS_TSV"
  printf 'fileB\tgitB\t-\n'    >> "$OIDS_TSV"
  build_tree4
  grep -q $'^fileA\t100\tshaA\tgitA$' "$TREE4"
  grep -q $'^fileB\t5\t-\tgitB$' "$TREE4"
  rm -rf "$TMPD"
}

@test "classify_diff: unchanged / changed (incl. same size) / new / stale" {
  TMPD="$(mktemp -d)"
  TREE4="$TMPD/tree4"
  printf 'a\t100\tsha_a\t-\n'  >  "$TREE4"   # unchanged
  printf 'b\t10\t-\tgitb2\n'   >> "$TREE4"   # changed (git oid differs)
  printf 'c\t200\tsha_c2\t-\n' >> "$TREE4"   # changed: SAME size, different sha
  printf 'e\t50\tsha_e\t-\n'   >> "$TREE4"   # new
  m="$TMPD/m"
  printf 'a\t100\tsha_a\t-\n'  >  "$m"
  printf 'b\t10\t-\tgitb1\n'   >> "$m"
  printf 'c\t200\tsha_c1\t-\n' >> "$m"
  printf 'd\t5\t-\tgitd\n'     >> "$m"       # stale (gone from tree)
  classify_diff 1 "$m"
  [ "$(cut -f1 "$CLS_UNCH"    | sort | tr '\n' ' ')" = "a " ]
  [ "$(cut -f1 "$CLS_CHANGED" | sort | tr '\n' ' ')" = "b c " ]
  [ "$(cut -f1 "$CLS_NEW"     | sort | tr '\n' ' ')" = "e " ]
  [ "$(cut -f1 "$CLS_STALE"   | sort | tr '\n' ' ')" = "d " ]
  rm -rf "$TMPD"
}

@test "classify_diff falls back to on-disk size when there is no manifest" {
  TMPD="$(mktemp -d)"; DEST="$TMPD/dest"; mkdir -p "$DEST"
  printf 'AAAA' > "$DEST/have"                 # 4 bytes present
  TREE4="$TMPD/tree4"
  printf 'have\t4\tsha_h\t-\n'    >  "$TREE4"   # present at full size -> unchanged
  printf 'missing\t9\tsha_m\t-\n' >> "$TREE4"   # absent -> new
  : > "$TMPD/empty"
  classify_diff 0 "$TMPD/empty"
  [ "$(cut -f1 "$CLS_UNCH")" = "have" ]
  [ "$(cut -f1 "$CLS_NEW")" = "missing" ]
  [ ! -s "$CLS_STALE" ]
  rm -rf "$TMPD"
}

@test "write_manifest + read round-trip, header parse, and kept-stale extras" {
  TMPD="$(mktemp -d)"; DEST="$TMPD/dest"; mkdir -p "$DEST"
  DEST_REAL="$(cd "$DEST" && pwd -P)"; REV=main; REPO_COMMIT=abc123
  printf 'AAAA' > "$DEST/f1"
  printf 'BB'   > "$DEST/f2"
  printf 'S'    > "$DEST/stale1"
  TREE4="$TMPD/tree4"
  printf 'f1\t4\tsha1\t-\n' >  "$TREE4"
  printf 'f2\t2\t-\tgit2\n' >> "$TREE4"
  extra="$TMPD/extra"; printf 'stale1\t1\t-\tgits\n' > "$extra"
  write_manifest "$extra"
  [ -f "$DEST/.hfget/manifest.tsv" ]
  read_manifest_header "$DEST"
  [ "$MANIFEST_REV" = "main" ]
  [ "$MANIFEST_COMMIT" = "abc123" ]
  rows="$(read_manifest_rows "$DEST")"
  printf '%s\n' "$rows" | grep -q $'^f1\t4\tsha1\t-$'
  printf '%s\n' "$rows" | grep -q '^stale1'   # kept-stale extra is preserved
  rm -rf "$TMPD"
}

@test "filter_cls keeps only paths matching includes/excludes" {
  TMPD="$(mktemp -d)"
  f="$TMPD/cls"
  printf 'a.gguf\t1\t-\t-\n' >  "$f"
  printf 'b.txt\t1\t-\t-\n'  >> "$f"
  INCLUDES=('*.gguf'); EXCLUDES=()
  filter_cls "$f"
  [ "$(cut -f1 "$f" | tr '\n' ' ')" = "a.gguf " ]
  rm -rf "$TMPD"
}

@test "manifest records and reads back the download filter" {
  TMPD="$(mktemp -d)"; DEST="$TMPD/dest"; mkdir -p "$DEST"
  DEST_REAL="$(cd "$DEST" && pwd -P)"; REV=main; REPO_COMMIT=xyz
  printf 'AAAA' > "$DEST/keep.gguf"
  TREE4="$TMPD/tree4"; printf 'keep.gguf\t4\tsha\t-\n' > "$TREE4"
  INCLUDES=('*Q8_0*'); EXCLUDES=('*foo*')
  write_manifest
  INCLUDES=(); EXCLUDES=()
  read_manifest_header "$DEST"
  [ "${MANIFEST_INCLUDES[*]}" = "*Q8_0*" ]
  [ "${MANIFEST_EXCLUDES[*]}" = "*foo*" ]
  rm -rf "$TMPD"
}

@test "discover_models finds org/model dirs carrying a manifest" {
  base="$(mktemp -d)"
  mkdir -p "$base/orgA/modelX/.hfget" "$base/orgB/modelY/.hfget" "$base/orgC/plain"
  : > "$base/orgA/modelX/.hfget/manifest.tsv"
  : > "$base/orgB/modelY/.hfget/manifest.tsv"
  [ "$(discover_models "$base" | sort | tr '\n' ' ')" = "orgA/modelX orgB/modelY " ]
  rm -rf "$base"
}
