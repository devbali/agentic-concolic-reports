#!/bin/bash
# =============================================================================
# P31 (copy of _p30_pass.sh, which is NOT edited -- it is P30's pass of record.
# ONE change: the blanket one-pass rule is now OPT-OUT. The owner raised the
# cage to MemoryMax=32G/High=30G (flat) on 2026-09-13, and the coordinator
# therefore DROPPED the "no coverage_report.py pass anywhere" hold, replacing it
# with (1) one heavy stage of ours at a time, (2) the memory invariant against
# the LIVE cap, (3) a CPU guard on the confinement gate. `wait_no_other_pass`
# was the memory-era rule; with P31_SKIP_ONEPASS=1 it is SKIPPED and the reason
# is logged. Default (unset) keeps the old behaviour, so this file also
# reproduces P30 exactly.
# ---- original header ----
# P30 (copy of _p29_pass.sh, which is NOT edited — it is P29's pass of
# record). Adds DISCIPLINE §16f (FORECLOSURE_SUBCONJUNCTIONS, width, budget)
# to the coverage stage's env and SUBCONJ_ to the verdict grep. Nothing else.
# P26 step A4 — snapshot + prune + ONE CHECKPOINTED COVERAGE PASS in the
# confinement-wired driver's OR-REFINED configuration (§82.2/§82.4's `P25OR`
# stage), on the corpus the P26 drive just extended.
#
#   usage: bash _p30_pass.sh <TAG> <DRIVETAG> <BASELIST>
#
# `_p15_pass.sh` is NOT edited (it is the pass of record for P15..P24 and a
# rerun must reproduce them). This is that script's three stages with the five
# confinement variables set EXPLICITLY instead of left to the engine default,
# so the log names the reading it ran under (§82.1's whole finding), plus
# FOOTPRINTS_OUT and the C7 heartbeat.
#   SKIP_COMPLETION=1        the gate is its own stage (RUNBOOK §4)
#   MAX_MISSING_PER_CLIQUE=1 §16d
#   COVERAGE_CHECKPOINT      per round, keyed on corpus+knobs+engine source
# Verdict: `P31-PASS-DONE <TAG>` / `P31-PASS-FAILED <stage>`.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
TAG="${1:?usage: _p30_pass.sh <TAG> <DRIVETAG> <BASELIST>}"
DRIVETAG="${2:-$TAG}"
BASE="${3:-$B/_snapshot_pruned_P24.txt}"
[ -f "$BASE" ] || BASE="$B/$3"
STAMP="${STAMP:-20260913}"
low=$(echo "$TAG" | tr 'A-Z' 'a-z')
L="$B/_p31_pass_${TAG}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
SNAP="$B/_snapshot_p31_${TAG}.txt"
LIST="$B/_snapshot_pruned_${TAG}.txt"
COV_OUT="$B/_cov_FINAL_${TAG}_${STAMP}.json"
COV_CKPT="$B/_cov_p31_${low}.ckpt.jsonl"

say "=== P31 PASS $TAG (OR-refined)  base=$(basename "$BASE")  drivetag=$DRIVETAG ==="
say "  engine coverage.py       md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
say "  batch coverage_report.py md5 $(md5sum "$B/coverage_report.py" | cut -d' ' -f1)"

if [ "$DRIVETAG" = "-" ]; then
  say "stages 1/2 SKIPPED — reusing $(basename "$LIST")"
  [ -s "$LIST" ] || { say "P31-PASS-FAILED snapshot"; exit 3; }
else
  nb=$(wc -l < "$BASE")
  find "$B" -maxdepth 1 -name "dump_*${DRIVETAG}*.json" > "$B/_new_p31_${TAG}.txt"
  nn=$(wc -l < "$B/_new_p31_${TAG}.txt")
  cat "$BASE" "$B/_new_p31_${TAG}.txt" | sed 's#^\./#'"$B"'/#' | sort -u > "$SNAP"
  say "P31-PASS-1 snapshot: base $nb + new $nn (label *${DRIVETAG}*) = $(wc -l < "$SNAP") unique"
  [ "$nn" = 0 ] && { say "  *** drive wrote 0 dumps with label *${DRIVETAG}* ***"; say "P31-PASS-FAILED snapshot"; exit 3; }
  say "P31-PASS-2 prune (cap 3G) -> $(basename "$LIST")"
  cage "p31prune${TAG}.scope" 3G \
    env DUMP_LIST="$SNAP" PYTHONPATH=/tmp/claude-1000/pareng:/home/dev/project/src COVERAGE_PAR=auto JAVA_TOOL_OPTIONS= \
        python3 -u "$B/_prune_corpus.py" --out "$LIST" > "$B/_p31_prune_${TAG}.log" 2>&1
  grep -q 'distinct outcome profiles' "$B/_p31_prune_${TAG}.log" || { say "P31-PASS-FAILED prune"; tail -20 "$B/_p31_prune_${TAG}.log" | tee -a "$L"; exit 4; }
  grep 'distinct outcome profiles' "$B/_p31_prune_${TAG}.log" | tee -a "$L"
fi
say "  DUMP_LIST $(basename "$LIST")  $(wc -l < "$LIST") profiles"
[ -s "$COV_CKPT" ] && say "  RESUMING: $(wc -l < "$COV_CKPT") demand-set record(s) in $(basename "$COV_CKPT")"

# ONE-COVERAGE-PASS-ON-THE-BOX (COORDINATOR, 2026-09-13 05:3x, after the cage
# hit 19.6G: gate 7.9G + this pass 4.7G + notifications' pass 5.1G). Before a
# coverage pass launches, NO OTHER ENDPOINT's coverage_report.py may be running.
# Drives are explicitly exempt and still overlap. The memory headroom check in
# `_cage.sh`'s gate_launch is UNCHANGED and still runs after this one.
# Matched by PATH so it can never match this endpoint's own pass (not yet
# started here) nor the shell that is asking.
wait_no_other_pass() {
  local w=0 busy
  while :; do
    busy=$(pgrep -af "coverage_report\.py" 2>/dev/null \
           | grep -v "posts_show/coverage_report.py" | head -1)
    [ -z "$busy" ] && { [ "$w" -gt 0 ] && say "  one-pass rule: other endpoints clear after ${w}s"; return 0; }
    [ $((w % 600)) -eq 0 ] && say "  one-pass rule: HOLD (${w}s) on $(echo "$busy" | cut -c1-90)"
    sleep 30; w=$((w+30))
  done
}
if [ "${P31_SKIP_ONEPASS:-0}" = 1 ]; then
  say "  one-pass rule SKIPPED (P31_SKIP_ONEPASS=1): cage is flat 32G, the"
  say "  coordinator replaced this hold with the gate CPU guard (2026-09-13)."
  say "  other passes seen right now: $(pgrep -af 'python3.*coverage_report\.py' 2>/dev/null | grep -v shell-snapshots | grep -v 'posts_show/coverage_report.py' | sed 's#.*results3/##;s# .*##' | tr '\n' ' ')"
else
  wait_no_other_pass
fi

say "P30-PASS-3 COVERAGE LAYER — OR-refined, SKIP_COMPLETION=1, MAX_MISSING_PER_CLIQUE=1, cap ${PASS_CAP:-7G} FORECLOSURE_CONJUNCTIONS=${FORECLOSURE_CONJUNCTIONS:-1} FORECLOSURE_SUBCONJUNCTIONS=${FORECLOSURE_SUBCONJUNCTIONS:-1} W=${FORECLOSURE_CONJUNCTION_WIDTH:-3} BUDGET=${FORECLOSURE_CONJUNCTION_BUDGET:-20000} NO_RENDER_TEXT_SOURCE=${NO_RENDER_TEXT_SOURCE:-<unset>}"
cage "p30pass${TAG}.scope" "${PASS_CAP:-7G}" \
  /usr/bin/time -v -o "$B/_p30_cov_${TAG}.time" \
  env DUMP_LIST="$LIST" SUMMARY_OUT="$COV_OUT" \
      SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=1 \
      FORECLOSURE_CONJUNCTIONS="${FORECLOSURE_CONJUNCTIONS:-1}" \
      FORECLOSURE_SUBCONJUNCTIONS="${FORECLOSURE_SUBCONJUNCTIONS:-1}" \
      FORECLOSURE_CONJUNCTION_WIDTH="${FORECLOSURE_CONJUNCTION_WIDTH:-3}" \
      FORECLOSURE_CONJUNCTION_BUDGET="${FORECLOSURE_CONJUNCTION_BUDGET:-20000}" \
      NO_RENDER_TEXT_SOURCE="${NO_RENDER_TEXT_SOURCE:-}" \
      COVERAGE_CHECKPOINT="$COV_CKPT" \
      CONFINEMENT=1 CONF_STRICT=1 CONF_KEYING=coevaluated CONF_GATES=1 CONF_OR_SHARING=1 \
      MAX_CLIQUES=16384 \
      FOOTPRINTS_OUT="$B/_footprints_${TAG}.json" \
      HEARTBEAT_SECS=120 \
      PYTHONPATH=/tmp/claude-1000/pareng:/home/dev/project/src COVERAGE_PAR=auto JAVA_TOOL_OPTIONS= \
      python3 -u "$B/coverage_report.py" > "$B/_p30_cov_${TAG}.log" 2>&1
say "P30-PASS-3 exit=$?"
if grep -qE '^COMPLETE=' "$B/_p30_cov_${TAG}.log"; then
  grep -E '^\[confinement\]|^\[assumptions\]|^\[checkpoint\]|^\[foreclosure\]|^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|CONFINEMENT|CONJ_|SUBCONJ_|peak RSS|wrote|dump_errors)|CONF-WITHDRAWN|CONF-DISQUALIFIED|TREE-MISSING' \
       "$B/_p30_cov_${TAG}.log" | tee -a "$L"
  grep -E 'Maximum resident|Elapsed' "$B/_p30_cov_${TAG}.time" 2>/dev/null | tee -a "$L"
  say "P31-PASS-DONE $TAG"
else
  caged_verdict "p30pass${TAG}.scope" "$B/_p30_cov_${TAG}.log" '^COMPLETE=' | tee -a "$L"
  tail -25 "$B/_p30_cov_${TAG}.log" | sed 's/^/    /' | tee -a "$L"
  say "P31-PASS-FAILED pass"; exit 10
fi
