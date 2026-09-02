#!/usr/bin/env bats
#
# Offline unit tests for hfget's pure functions. These source the script (which
# skips all side effects when sourced) and call functions directly. No network.

setup() {
  HFGET="${BATS_TEST_DIRNAME}/../hfget"
  # Never let a test touch the developer's real ~/.hfget: point the queue
  # state at a throwaway dir BEFORE sourcing (QDIR is derived at source time).
  UNIT_STATE="$(mktemp -d)"
  export HFGET_STATE_DIR="$UNIT_STATE" HFGET_NOCAFFEINE=1
  # shellcheck disable=SC1090
  source "$HFGET"
}

teardown() {
  [ -n "${UNIT_STATE:-}" ] && rm -rf "$UNIT_STATE"
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

@test "discover_models finds org/model dirs carrying a manifest, and bare-id models" {
  base="$(mktemp -d)"
  mkdir -p "$base/orgA/modelX/.hfget" "$base/orgB/modelY/.hfget" "$base/orgC/plain" "$base/gpt2/.hfget"
  : > "$base/orgA/modelX/.hfget/manifest.tsv"
  : > "$base/orgB/modelY/.hfget/manifest.tsv"
  : > "$base/gpt2/.hfget/manifest.tsv"          # canonical model with a bare id
  [ "$(discover_models "$base" | sort | tr '\n' ' ')" = "gpt2 orgA/modelX orgB/modelY " ]
  rm -rf "$base"
}

# ---------------------------------------------------------------- safety ----

@test "fmt_class classifies formats by extension" {
  [ "$(fmt_class a/pytorch_model.bin)" = "pickle" ]
  [ "$(fmt_class sd.ckpt)" = "pickle" ]
  [ "$(fmt_class model.nemo)" = "pickle" ]
  [ "$(fmt_class tf_model.h5)" = "keras" ]
  [ "$(fmt_class modeling_x.py)" = "code" ]
  [ "$(fmt_class dir.v2/w.SafeTensors)" = "safe" ]
  [ "$(fmt_class Q4.GGUF)" = "safe" ]
  [ "$(fmt_class unet/model.onnx)" = "safe" ]
  [ "$(fmt_class README.md)" = "other" ]
  [ "$(fmt_class noext)" = "other" ]
}

@test "fmt_summary lists risky formats first and names their extensions" {
  t="$(mktemp)"
  printf 'a.safetensors\t1\nb.safetensors\t2\nc.bin\t3\nd.pt\t4\nconfig.json\t5\ne.gguf\t6\n' > "$t"
  [ "$(fmt_summary "$t" 1)" = "pickle ×2 (.bin, .pt) · safetensors ×2 · gguf ×1" ]
  printf 'config.json\t1\nREADME.md\t2\n' > "$t"
  [ "$(fmt_summary "$t" 1)" = "(no weight files)" ]
  # a precomputed key column (audit, after sniffing) overrides the extension
  printf 'model.safetensors\t9\tpickle\n' > "$t"
  [ "$(fmt_summary "$t" 1 3)" = "pickle ×1 (.safetensors)" ]
  rm -f "$t"
}

@test "sniff_format recognises gguf / safetensors / pickle / torch-zip from the first bytes" {
  d="$(mktemp -d)"
  printf 'GGUF\003\000\000\000rest' > "$d/g"
  printf '\132\000\000\000\000\000\000\000{"__metadata__":{}}' > "$d/s"     # u64 LE header length, then "{"
  printf '\200\004\225\000' > "$d/p"                                            # pickle protocol 4
  printf 'PK\003\004%026d' 0 > "$d/t"; printf 'archive/data.pkl' >> "$d/t"     # zip whose first member is data.pkl
  printf 'PK\003\004%026d' 0 > "$d/z"; printf 'hello.txt' >> "$d/z"
  printf 'just text' > "$d/o"
  : > "$d/e"
  [ "$(sniff_format "$d/g")" = "gguf" ]
  [ "$(sniff_format "$d/s")" = "safetensors" ]
  [ "$(sniff_format "$d/p")" = "pickle" ]
  [ "$(sniff_format "$d/t")" = "torch-zip" ]
  [ "$(sniff_format "$d/z")" = "zip" ]
  [ "$(sniff_format "$d/o")" = "other" ]
  [ "$(sniff_format "$d/e")" = "other" ]
  rm -rf "$d"
}

@test "scan_state_for intersects the scanner's flagged files with a selection" {
  TMPD="$(mktemp -d)"
  sel="$TMPD/sel"; printf '10\t-\tconfig.json\n20\tsha\tpytorch_model.bin\n' > "$sel"
  SCAN_ISSUES="$TMPD/issues"
  printf 'pytorch_model.bin\tunsafe\nother.bin\tunsafe\n' > "$SCAN_ISSUES"; SCAN_DONE=1
  scan_state_for "$sel" 3
  [ "$N_FLAG" = "1" ]; [ "$SCAN_STATE" = "flagged" ]
  grep -q $'^pytorch_model.bin\tunsafe$' "$TMPD/flagged"
  printf 'other.bin\tunsafe\n' > "$SCAN_ISSUES"        # flagged upstream, but not selected
  scan_state_for "$sel" 3
  [ "$N_FLAG" = "0" ]; [ "$SCAN_STATE" = "clear" ]
  : > "$SCAN_ISSUES"; SCAN_DONE=0                       # nothing flagged, scans still running
  scan_state_for "$sel" 3
  [ "$N_FLAG" = "0" ]; [ "$SCAN_STATE" = "partial" ]
  SCAN_DONE=''
  scan_state_for "$sel" 3
  [ "$SCAN_STATE" = "unknown" ]
  rm -rf "$TMPD"
}

@test "scan_gate refuses a flagged selection (exit 2) unless --allow-unsafe; HFGET_SCAN=off skips it" {
  TMPD="$(mktemp -d)"; MODEL=org/model
  sel="$TMPD/sel"; printf '10\t-\tconfig.json\n20\tsha\tpytorch_model.bin\n' > "$sel"
  # Pre-seed the per-run cache so scan_status makes no network call.
  SCAN_FOR=$MODEL; SCAN_DONE=1; SCAN_REPO=flagged
  SCAN_ISSUES="$TMPD/issues"; printf 'pytorch_model.bin\tunsafe\n' > "$SCAN_ISSUES"
  ALLOW_UNSAFE=0
  run scan_gate "$sel" download 3
  [ "$status" -eq 2 ]
  [[ "$output" == *"FLAGGED"* ]]
  [[ "$output" == *"refusing to download"* ]]
  ALLOW_UNSAFE=1
  run scan_gate "$sel" download 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"--allow-unsafe given"* ]]
  ALLOW_UNSAFE=0
  HFGET_SCAN=off run scan_gate "$sel" download 3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # a clean selection in a flagged repo passes, and says so
  printf '10\t-\tconfig.json\n' > "$sel"
  run scan_gate "$sel" download 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"not among the files to fetch"* ]]
  rm -rf "$TMPD"
}

@test "manifest header records and reads back the scanner verdict and timestamp" {
  TMPD="$(mktemp -d)"; DEST="$TMPD/dest"; mkdir -p "$DEST"
  DEST_REAL="$(cd "$DEST" && pwd -P)"; REV=main; REPO_COMMIT=abc; INCLUDES=(); EXCLUDES=()
  printf 'AAAA' > "$DEST/f1"
  TREE4="$TMPD/tree4"; printf 'f1\t4\tsha1\t-\n' > "$TREE4"
  SCAN_STATE=partial
  write_manifest
  grep -q ' scan=partial$' "$DEST/.hfget/manifest.tsv"
  read_manifest_header "$DEST"
  [ "$MANIFEST_SCAN" = "partial" ]
  [[ "$MANIFEST_UPDATED" == 20*T*Z ]]
  rm -rf "$TMPD"
}

@test "audit --offline reports recorded verdicts, hidden pickles and filters, exit 2 when anything is flagged" {
  base="$(mktemp -d)"
  mkdir -p "$base/org/clean/.hfget" "$base/org/bad/.hfget" "$base/org/hidden/.hfget"
  printf '# hfget 2.9.0 rev=main commit=x updated=2026-09-01T00:00:00Z scan=clear\nmodel.safetensors\t4\tsha\t-\n' > "$base/org/clean/.hfget/manifest.tsv"
  printf 'AAAA' > "$base/org/clean/model.safetensors"
  printf '# hfget 2.9.0 rev=main commit=x updated=2026-08-24T00:00:00Z scan=flagged\npytorch_model.bin\t4\tsha\t-\n' > "$base/org/bad/.hfget/manifest.tsv"
  printf 'AAAA' > "$base/org/bad/pytorch_model.bin"
  # a "safetensors" whose bytes are a pickle, big enough (>= 1 MB) to be sniffed
  printf '# hfget 2.9.0 rev=main commit=x updated=2026-09-01T00:00:00Z scan=unknown\n# include\t*.safetensors\nmodel.safetensors\t1100003\tsha\t-\n' > "$base/org/hidden/.hfget/manifest.tsv"
  { printf '\200\004\225'; head -c 1100000 /dev/zero; } > "$base/org/hidden/model.safetensors"
  HFGET_NOCAFFEINE=1 run bash "$HFGET" audit "$base" --offline
  [ "$status" -eq 2 ]
  [[ "$output" == *"org/clean"*"recorded: clear"* ]]
  [[ "$output" == *"org/bad"*"recorded: flagged"* ]]
  [[ "$output" == *"HIDDEN PICKLE: model.safetensors"* ]]
  [[ "$output" == *"filter *.safetensors"* ]]
  [[ "$output" == *"1 FLAGGED"* ]]
  rm -rf "$base"
}

@test "rmdir_upto removes emptied dirs below the model dir but never the model dir or above" {
  base="$(mktemp -d)"; dest="$base/org/model"
  mkdir -p "$dest/a/b/c" "$dest/a/other"
  rmdir_upto "$dest" "$dest/a/b/c"
  [ ! -d "$dest/a/b" ]          # emptied chain removed
  [ -d "$dest/a" ]              # sibling keeps this one alive
  rmdir "$dest/a/other"
  rmdir_upto "$dest" "$dest/a"
  [ ! -d "$dest/a" ]
  [ -d "$dest" ]                # the model dir itself survives even when empty
  rmdir_upto "$dest" "$base/org"   # outside the top: refused
  [ -d "$base/org" ]
  rm -rf "$base"
}

@test "dest_safety_nets honors --require-mount and warns on the /Volumes trap" {
  d="$(mktemp -d)"
  REQUIRE_MOUNT=0
  run dest_safety_nets "$d" 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  REQUIRE_MOUNT=1
  run dest_safety_nets "$d" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"--require-mount"*"not on a network mount"* ]]
  REQUIRE_MOUNT=0
  run dest_safety_nets "/Volumes/definitely-not-mounted-$$" 0
  [ "$status" -eq 0 ]
  if [ "$(uname)" = "Darwin" ]; then
    [[ "$output" == *"resolves to the local disk"* ]]
    [[ "$output" != *"--require-mount"* ]]   # commands without the flag don't advertise it
  fi
  rm -rf "$d"
}

@test "foreign_hfget_pids can be narrowed to one model id" {
  # Fake another 'hfget download' of a model: argv[0] is what ps shows.
  bash -c 'exec -a "bash /somewhere/hfget download org/model-a /dest" sleep 20' &
  fake=$!
  sleep 0.3
  all=$(foreign_hfget_pids)
  [[ " $all " == *" $fake "* ]]
  mine=$(foreign_hfget_pids "org/model-a")
  [[ " $mine " == *" $fake "* ]]
  other=$(foreign_hfget_pids "org/model")          # a prefix must not match
  [[ " $other " != *" $fake "* ]]
  kill "$fake" 2>/dev/null || true
  wait "$fake" 2>/dev/null || true
}

# ------------------------------------------------------------ queue ops -----

# Point the queue-state globals at a throwaway dir so these never touch ~/.hfget.
_use_temp_queue() {
  QDIR="$1"; QF="$1/queue.tsv"; CF="$1/current.tsv"; FF="$1/failed.tsv"
  DL="$1/done.log"; RL="$1/runner.log"; RP="$1/runner.pid"; SF="$1/stop"
  CLP="$1/current.logpath"; LOCKD="$1/lock"
}

@test "clear --failed dismisses failed entries but leaves pending" {
  d="$(mktemp -d)"; _use_temp_queue "$d"
  printf 'org/pending\t2026-01-01T00:00:00Z\t/dest\n' > "$QF"
  printf 'org/dead\t2026-01-01T00:00:00Z\t/dest\n'    > "$FF"
  cmd_clear --failed
  [ ! -s "$FF" ]        # failed cleared
  [ -s "$QF" ]          # pending untouched
  rm -rf "$d"
}

@test "rm <model> removes the model from both pending and failed" {
  d="$(mktemp -d)"; _use_temp_queue "$d"
  printf 'org/keep\t2026-01-01T00:00:00Z\t/dest\n'  > "$QF"
  printf 'org/dead\t2026-01-01T00:00:00Z\t/dest\n' >> "$QF"
  printf 'org/dead\t2026-01-01T00:00:00Z\t/dest\n'  > "$FF"
  cmd_rm org/dead
  grep -q '^org/keep' "$QF"
  ! grep -q '^org/dead' "$QF"
  [ ! -s "$FF" ]        # the failed copy is dismissed too
  rm -rf "$d"
}
