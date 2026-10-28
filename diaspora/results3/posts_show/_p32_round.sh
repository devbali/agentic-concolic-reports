#!/bin/bash
# =============================================================================
# P31 ROUND 9 / P32 ROUND 10 — the BASE-RULE round, re-entrant on TAG.  (P32 COPY: hold list reduced to the
# gate CPU guard + the memory invariant. _p31_round.sh is NOT edited.)
#
# WHAT IT TESTS. §89.10 localised round 8's 1 636 contradicted literals (1 636
# of 1 636 on the length gate) to the BASE CHOICE, not the seed writer: 566 of
# 569 seeds sat on a base that does not walk the cube's enabling gates and does
# not realise its upstream emptiness pins. `_p31_construct.py` makes both a
# HARD FILTER. **The test of the rule is that the contradicted length-gate
# class drops to ~0** — the number to read off S6, nothing else.
#
# STAGES (resume with P31_FROM=<n>; every stage is skipped when its own output
# is already on disk, so a re-run after a kill costs only the unfinished one)
#   S0 hold while a notifications pass/drive is active   (the one-pass rule)
#   S1 PASS P30B2      round 8's OUTSTANDING pass — §89.7's "NEXT"; it also
#                      writes _snapshot_pruned_P30B2.txt, which S2 needs
#   S2 EMIT P31A       OR-refined census + §16f emission on that list
#                      (~21 min, 5 GB — the P30 emission is NOT reusable here,
#                      round 8's 569 dumps changed the residue)
#   S3 REBUILD P31A    bootstrap gaps -> FRESH index (round 8's dumps are now
#                      candidate bases) -> gaps -> P31 construct
#   S4 DRYCHECK        offline, no JRuby. A violation ABORTS before the drive.
#   S5 DRIVE           DRIVE_PAR=2 CONCOLIC_SLOTS=4, chunk 200
#   S6 EXPLAIN         per key — THE VERDICT OF THE ROUND
#   S7 PASS P31A2      §16e + §16f, W=3
#   S8 OR CENSUS P31B  the residue for the next round
#
# Verdict: P31-ROUND-DONE / P31-ROUND-FAILED <stage>
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
. "$B/_p32_guard.sh"
export P31_SKIP_ONEPASS=1
TAG="${TAG:-P31A}"
FROM="${P31_FROM:-0}"
STAMP="${STAMP:-20260913}"
L="$B/_p31_round.log"; : >> "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
T0=$(date +%s)
say "=== P31 ROUND 9 ($TAG) — the base rule, from stage $FROM (P32 runner) ==="

# ---------------------------------------------------------------- S0 the hold
# ---------------------------------------------------------------- THE GUARDS
# COORDINATOR, 2026-09-13 21:2x. The owner raised the cage to a FLAT
# MemoryMax=32G / MemoryHigh=30G and retired the 19G<->24G hold watchers, so
# memory no longer forces this endpoint to queue behind notifications' passes.
# The blanket "no coverage_report.py pass anywhere" hold is therefore DROPPED
# and replaced by three rules, implemented in `_p31_guard.sh`:
#   (1) ONE heavy stage of MINE at a time — structural, this script is
#       sequential and waits on every caged scope.
#   (2) the memory invariant against the LIVE cap — already exact in
#       `_cage.sh:gate_launch` (reads MemoryMax from the slice at each launch,
#       requires free avail >= cap+512M AND MemoryMax-MemoryCurrent >= cap,
#       and launches with --slice=concolic-cov.slice). `mem_line` RECORDS it.
#   (3) a CPU guard on `posts-p26-gate-v2-20260913`, the long pole, sampled
#       immediately before each stage and again 10 minutes in.
# WHAT STILL HOLDS: notifications' engine section, its own assumption_checker,
# the audits chain and its drives — the coordinator named only the
# coverage_report.py clause for removal, so the rest stand. Every matcher is
# path-qualified and filters `shell-snapshots` (§91.5b: a bare-name matcher
# livelocks against other agents' watcher shells).
hold(){
  # ==========================================================================
  # P32, 2026-09-14 03:5x — THE NOTIFICATIONS HOLDS ARE DROPPED (coordinator).
  # The hold list below this comment used to name notifications' engine
  # section, its assumption_checker, `_c7_audits`, the AUDITS_CHECKPOINT
  # wrapper, `notif-*` units and any endpoint's coverage_report.py. The
  # coordinator withdrew all of them as their own design error: the list was
  # written when the cage was 4 GB and every job competed for it, and was never
  # revised when the owner raised the cage to 32 GB. The audit suite it held on
  # is 87 MB of RSS and I/O-bound, and holding on it cost this round 2 h 40 m
  # on one stage (~5 h across the night) for no resource reason.
  #
  # EXACTLY TWO RULES REMAIN:
  #   (1) the memory invariant against the LIVE cap — enforced, not advised, in
  #       `_cage.sh:gate_launch` at every single launch (free avail >= cap+512M
  #       AND MemoryMax-MemoryCurrent >= cap, always --slice=concolic-cov.slice).
  #       Nothing here duplicates it; `mem_line` records it in the log.
  #   (2) the gate CPU guard — 300 s windows, two consecutive readings below
  #       GATE_MIN_RATE (0.7/s) before standing down. `stage_begin` measures it
  #       and drops $STARVED_FLAG; THIS function is the stand-down itself.
  #
  # The stand-down no longer waits on another agent's job (there is no longer a
  # reason to think notifications' pass is what starved the gate). It waits on
  # THE GATE'S OWN RATE: hold here until a fresh 300 s window reads at or above
  # the threshold. That cannot livelock — the round is idle while it waits, so
  # if this round was the cause the rate recovers within one window, and if it
  # was not, the window clears on the first sample and the stage proceeds.
  # ==========================================================================
  local w=0 r
  [ -f "$STARVED_FLAG" ] || return 0
  say "  GATE STAND-DOWN: the previous stage drove the gate below ${GATE_MIN_RATE}/s on two"
  say "    consecutive windows. Waiting for a 300 s window >= ${GATE_MIN_RATE}/s before starting."
  while [ -f "$STARVED_FLAG" ]; do
    r=$(gate_win_rate 300)
    if _below "$r"; then
      w=$((w+300))
      say "  stand-down (${w}s): gate window ${r}/s still below ${GATE_MIN_RATE}/s"
    else
      rm -f "$STARVED_FLAG"
      say "  stand-down lifted after ${w}s: gate window ${r}/s >= ${GATE_MIN_RATE}/s"
    fi
  done
  return 0
}

# stage_begin / stage_end LIVE IN `_p31_guard.sh`, sourced above — deliberately
# NOT here. The coordinator refined the sampler twice in one hour (window 120 s
# -> ~300 s; one sub-0.7 window -> TWO CONSECUTIVE), and both times this script
# was RUNNING. A sampler defined here cannot be refined without either editing a
# running script or throwing away a stage; defined in the sourced guard it can.
# The refinements themselves, and why they are right:
#   * a batch is 40 probes, so at ~1 probe/s a 120 s window holds only ~3
#     batches and ONE slow batch reads as starvation. 300 s halves that noise.
#   * two consecutive sub-0.7 windows are required before standing down, so a
#     single stall does not idle the round for nothing. Both windows are logged
#     with their batch deltas, so the reading can be checked, not believed.

# ------------------------------------------- S1 round 8's outstanding pass
if [ "$FROM" -le 1 ] && [ -z "$P32_SKIP_S1" ] && ! ls "$B"/_cov_FINAL_P30B2_*.json >/dev/null 2>&1; then
  say "S1 PASS P30B2 — round 8's outstanding pass (§89.7 NEXT)"
  stage_begin S1 7
  STAMP="$STAMP" PASS_CAP=7G FORECLOSURE_CONJUNCTIONS=1 FORECLOSURE_SUBCONJUNCTIONS=1 \
  FORECLOSURE_CONJUNCTION_WIDTH=3 FORECLOSURE_CONJUNCTION_BUDGET=20000 \
    bash "$B/_p31_pass.sh" P30B2 P30B "$B/_snapshot_pruned_P30C.txt" >> "$L" 2>&1
  stage_end S1
  grep -qE 'P31-PASS-DONE' "$B/_p31_pass_P30B2.log" || {
    say "P31-ROUND-FAILED s1-pass-P30B2"; tail -20 "$B/_p31_pass_P30B2.log" | tee -a "$L"; exit 4; }
  grep -E '^\[foreclosure\]|^COMPLETE=|^GENUINE=|^dumps_loaded|^DEMAND_SETS|^CONJ_|^SUBCONJ_|^CONFINEMENT=|peak RSS|distinct outcome' \
       "$B/_p31_pass_P30B2.log" | tee -a "$L"
else
  say "S1 SKIPPED (P30B2 pass already on disk)"
fi
LIST="${P32_LIST:-$B/_snapshot_pruned_P30B2.txt}"
[ -s "$LIST" ] || { say "P31-ROUND-FAILED s1-no-list"; exit 4; }

# ------------------------------------------------------------- S2 the emission
if [ "$FROM" -le 2 ] && [ ! -s "$B/_p31_emit_${TAG}.jsonl" ]; then
  say "S2 EMIT $TAG (OR-refined census + §16f, W=3) on $(basename "$LIST")"
  hold
  stage_begin S2 7
  CENSUS_MODES="${CENSUS_MODES:-prod,16f}" EMIT_CAP_MEM=7G \
  FORECLOSURE_CONJUNCTION_WIDTH=3 FORECLOSURE_CONJUNCTION_BUDGET=20000 \
    bash "$B/_p31_emit.sh" "$TAG" "$LIST" >> "$L" 2>&1
  stage_end S2
  grep -qE "P31-EMIT-DONE" "$B/_p31_emit_${TAG}.log" || {
    say "P31-ROUND-FAILED s2-emit"; tail -20 "$B/_p31_emit_${TAG}.log" | tee -a "$L"; exit 5; }
else
  say "S2 SKIPPED (_p31_emit_${TAG}.jsonl already on disk)"
fi
JSONL="$B/_p31_emit_${TAG}.jsonl"
[ -s "$JSONL" ] || { say "P31-ROUND-FAILED s2-no-emission"; exit 5; }
say "S2 emission: $(wc -l < "$JSONL") cubes"

# -------------------------------------------------------------- S3 the rebuild
if [ "$FROM" -le 3 ] && [ ! -s "$B/_p15_manifest_${TAG}.json" ]; then
  say "S3 REBUILD $TAG (cap 3 cubes/set) — P31 construct, HARD pin filter"
  hold
  stage_begin S3 6
  OLD_INDEX="${P32_OLD_INDEX:-$B/_p30_index_P30B.pkl}" P23_MAX_PER_SET="${P23_MAX_PER_SET:-3}" \
  P23_MAX_TOTAL="${P23_MAX_TOTAL:-0}" \
    bash "$B/_p31_rebuild.sh" "$TAG" "$JSONL" "$LIST" >> "$L" 2>&1
  stage_end S3
  grep -qE 'P31-REBUILD-DONE' "$B/_p31_rebuild_${TAG}.log" || {
    say "P31-ROUND-FAILED s3-rebuild"; tail -25 "$B/_p31_rebuild_${TAG}.log" | tee -a "$L"; exit 6; }
else
  say "S3 SKIPPED (_p15_manifest_${TAG}.json already on disk)"
fi
say "S3 gaps=$(python3 -c "import json;print(len(json.load(open('$B/_p31_gaps_${TAG}.json'))))" 2>/dev/null)"
grep -E 'REALISES every cube emptiness pin|WALKS every enabling gate|admissible on BOTH|EXHAUSTED SPLITS|own dump' \
     "$B/_p31_construct_${TAG}.log" | tee -a "$L"

# ---------------------------------------------------- S4 the offline dry-check
say "S4 DRYCHECK (offline; a violation aborts before any drive)"
env P31_MANIFEST="$B/_p15_manifest_${TAG}.json" P31_GAPS="$B/_p31_gaps_${TAG}.json" \
    P31_DRYOUT="$B/_p31_drycheck_${TAG}.json" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u "$B/_p31_drycheck.py" > "$B/_p31_drycheck_${TAG}.log" 2>&1
grep -E 'V1 ok|V1 VIOLATION|V2 VIOLATION|V4 VIOLATION|V1b|P31-DRYCHECK' \
     "$B/_p31_drycheck_${TAG}.log" | tee -a "$L"
grep -qE '^P31-DRYCHECK-PASS' "$B/_p31_drycheck_${TAG}.log" || {
  say "P31-ROUND-FAILED s4-drycheck (NOT driving a batch whose bases do not hold their pins)"
  tail -20 "$B/_p31_drycheck_${TAG}.log" | tee -a "$L"; exit 7; }

# ----------------------------------------------------------------- S5 the drive
if [ "$FROM" -le 5 ] && ! grep -qE 'P15-DRIVE-DONE' "$B/_p15_drive_${TAG}.log" 2>/dev/null; then
  say "S5 DRIVE (DRIVE_PAR=2 CONCOLIC_SLOTS=4 chunk 200)"
  hold
  stage_begin S5 4
  before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
  SEEDSET="$TAG" DRIVE_PAR=2 CONCOLIC_SLOTS=4 \
    P15_MANIFEST="$B/_p15_manifest_${TAG}.json" \
    bash "$B/_p15_drive.sh" "$TAG" 200 >> "$L" 2>&1
  stage_end S5
  grep -qE 'P15-DRIVE-DONE' "$B/_p15_drive_${TAG}.log" || {
    say "P31-ROUND-FAILED s5-drive"; tail -20 "$B/_p15_drive_${TAG}.log" | tee -a "$L"; exit 8; }
  after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
  say "S5 $(grep -E 'P15-DRIVE-DONE' "$B/_p15_drive_${TAG}.log" | tail -1)   corpus ${before} -> ${after}"
else
  say "S5 SKIPPED (drive already done)"
fi

# --------------------------------------------------------------- S6 the verdict
say "S6 EXPLAIN per key — THE TEST OF THE BASE RULE"
cage "p31exp${TAG}.scope" 4G \
  env P15_TAG="$TAG" P15_SET="$TAG" P15_GAPS="$B/_p31_gaps_${TAG}.json" \
      P15_MANIFEST="$B/_p15_manifest_${TAG}.json" \
      P15_OUT="$B/_p31_explain_${TAG}.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_explain.py" > "$B/_p31_explain_${TAG}.log" 2>&1
caged_verdict "p31exp${TAG}.scope" "$B/_p31_explain_${TAG}.log" '^P15-EXPLAIN-DONE' | tee -a "$L"
grep -E 'WALKED|honoured|contradicted|never evaluated|cube literals|^  gaps|length gate' \
     "$B/_p31_explain_${TAG}.log" | head -24 | tee -a "$L"
say "S6 >>> ROUND 8 was: 187/569 walked, 84.8 % honoured, 1 636 CONTRADICTED, all"
say "S6 >>> on the length gate. The base rule works iff that column is ~0. <<<"

# ------------------------------------------------------------------ S7 the pass
say "S7 PASS ${TAG}2 (§16e + §16f, W=3, cap 7G)"
hold
stage_begin S7 7
STAMP="$STAMP" PASS_CAP=7G FORECLOSURE_CONJUNCTIONS=1 FORECLOSURE_SUBCONJUNCTIONS=1 \
FORECLOSURE_CONJUNCTION_WIDTH=3 FORECLOSURE_CONJUNCTION_BUDGET=20000 \
  bash "$B/_p31_pass.sh" "${TAG}2" "$TAG" "$LIST" >> "$L" 2>&1
stage_end S7
grep -qE 'P31-PASS-DONE' "$B/_p31_pass_${TAG}2.log" || {
  say "P31-ROUND-FAILED s7-pass"; tail -20 "$B/_p31_pass_${TAG}2.log" | tee -a "$L"; exit 9; }
grep -E '^\[assumptions\]|^\[foreclosure\]|^COMPLETE=|^GENUINE=|^dumps_loaded|^DEMAND_SETS|^CONJ_|^SUBCONJ_|^CONFINEMENT=|peak RSS|distinct outcome' \
     "$B/_p31_pass_${TAG}2.log" | tee -a "$L"

# --------------------------------------------------------------- S8 the census
say "S8 OR CENSUS ${TAG}B — the residue for round 10"
hold
stage_begin S8 7
CENSUS_MODES="prod,16f" EMIT_CAP_MEM=7G \
FORECLOSURE_CONJUNCTION_WIDTH=3 FORECLOSURE_CONJUNCTION_BUDGET=20000 \
  bash "$B/_p31_emit.sh" "${TAG}B" "$B/_snapshot_pruned_${TAG}2.txt" >> "$L" 2>&1
stage_end S8
grep -qE "P31-EMIT-DONE" "$B/_p31_emit_${TAG}B.log" || {
  say "P31-ROUND-FAILED s8-census"; tail -20 "$B/_p31_emit_${TAG}B.log" | tee -a "$L"; exit 10; }
say "S8 remaining: $(wc -l < "$B/_p31_emit_${TAG}B.jsonl") cubes"

say "P31-ROUND-DONE wall=$(( $(date +%s)-T0 ))s"
