#!/bin/bash
# =============================================================================
# P25 — the SAME P24 corpus under the three nested §16c readings.
#
#   OFF     confinement=0                  -> DISCIPLINE §16b
#   STRICT  or_sharing=0                   -> §16c strict one-sidedness
#   OR      (engine defaults)              -> §16c round-5 OR-refined
#
# One pass at a time, each CHECKPOINTED under its own file (the engine folds
# every confinement knob into the checkpoint header key, so the three can
# never read each other's records). Verdict per stage is `^COMPLETE=`.
#
# Judge this script by its last line: `P25-PASSES-DONE` or `P25-PASSES-FAILED`.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
LIST="${LIST:-$B/_snapshot_pruned_P24.txt}"
STAMP="${STAMP:-20260912}"
L="$B/_p25_conf_passes.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }

say "=== P25 CONFINEMENT PASSES  list=$(basename "$LIST") ($(wc -l < "$LIST") profiles) ==="
say "  engine coverage.py       md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
say "  batch coverage_report.py md5 $(md5sum "$B/coverage_report.py" | cut -d' ' -f1)"

run_one(){ # <TAG> <env assignments...>
  local TAG="$1"; shift
  local low; low=$(echo "$TAG" | tr 'A-Z' 'a-z')
  local OUT="$B/_cov_FINAL_${TAG}_${STAMP}.json"
  local CK="$B/_cov_${low}.ckpt.jsonl"
  local LOG="$B/_p25_cov_${TAG}.log"
  [ -s "$CK" ] && say "  RESUMING $TAG: $(wc -l < "$CK") record(s) in $(basename "$CK")"
  say "P25-$TAG START  -> $(basename "$OUT")  ckpt $(basename "$CK")"
  /usr/bin/time -v -o "$B/_p25_cov_${TAG}.time" \
    env DUMP_LIST="$LIST" SUMMARY_OUT="$OUT" \
        SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=1 \
        COVERAGE_CHECKPOINT="$CK" \
        FOOTPRINTS_OUT="$B/_footprints_${TAG}.json" \
        HEARTBEAT_SECS=120 \
        PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
        "$@" python3 -u "$B/coverage_report.py" > "$LOG" 2>&1
  local rc=$?
  say "P25-$TAG exit=$rc"
  if grep -qE '^COMPLETE=' "$LOG"; then
    grep -E '^\[confinement\]|^\[coverage\]|^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|CONFINEMENT|peak RSS|wrote)' "$LOG" | tee -a "$L"
    grep -E 'Maximum resident|Elapsed' "$B/_p25_cov_${TAG}.time" 2>/dev/null | tee -a "$L"
    say "P25-$TAG OK"
    return 0
  fi
  say "P25-$TAG *** NO VERDICT LINE — TREAT AS KILLED ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$L"
  return 1
}

run_one P25OFF    CONFINEMENT=0                 || { say "P25-PASSES-FAILED off";    exit 10; }
run_one P25STRICT CONF_OR_SHARING=0             || { say "P25-PASSES-FAILED strict"; exit 11; }
run_one P25OR     CONFINEMENT=1                 || { say "P25-PASSES-FAILED or";     exit 12; }

say "--- NESTING (demand sets; expect OR-refined and STRICT to SPLIT the 16b sets) ---"
for T in P25OFF P25STRICT P25OR; do
  say "  $T  $(grep -m1 -oE 'DEMAND_SETS=[0-9]+' "$B/_p25_cov_${T}.log")  $(grep -m1 -oE '^CONFINEMENT=[^;]+' "$B/_p25_cov_${T}.log")  $(grep -m1 -oE 'MISSING=[0-9]+' "$B/_p25_cov_${T}.log")"
done
say "P25-PASSES-DONE"
