#!/usr/bin/env bash
# P47 — posts_show CORPUS REGENERATION (stage 1: base exploration), 2026-09-25.
#
# WHY A NEW CORPUS AT ALL. The shipped corpus (720,279 dumps in the batch dir,
# 206,593 in _snapshot_pruned_P44FRESH2.txt) was driven with a targets tree
# that still carried boundary gap B-4: every STI relation's note was an
# exception string, in 96.6 % of dumps. `call_shape` is the currency of BOTH
# the engine's per-decision footprint and the assumption gate's access trace,
# so 451 of 460 ConfinementAssumption FAILs, both Reshare NOTE-MISMATCHes and
# a large share of note_fidelity's REDs are downstream of it. Notes are baked
# into dumps at exploration time, so nothing above the drive can repair them.
# See _CORPUS_INVALIDATED_B4_20260925.md and _P47_HANDOFF_20260925.md.
#
# ------------------------------------------------------------------------
# PARALLELISM — READ THIS BEFORE CHANGING IT.
#
# Prefix-directed DSE is DETERMINISTIC: same runner, same seeds, same targets
# => same worklist => the same paths in the same order. So N identical chains
# do not explore N times as much, they explore the SAME tree N times.
#
# MEASURED, 2026-09-25 (attempt 2 of this script's first design, stopped at
# 169 dumps): three chains differing only in LABEL_SUFFIX produced 145 dumps
# carrying 49 distinct path signatures -- chain1 vs chain2, chain1 vs chain3
# and chain2 vs chain3 each overlapped 48/48. Duplication factor 2.96.
#
# For contrast, the SHIPPED corpus has duplication factor 1.00: 6 000 sampled
# dumps, 6 000 distinct signatures. All-distinct is this project's norm, and
# duplicates are not free -- dump LOADING dominates every downstream check
# (~2.1 h for 206 k dumps), so a 3x corpus is a 3x tax on every pass for no
# coverage at all.
#
# THE ONLY SOUND PARALLEL AXIS AT THIS STAGE IS THE SCENARIO. run_dse.rb
# explores each of its four scenarios with its OWN worklist (`_scen.map { |p|
# explore(p) }`), so one process per scenario gives four genuinely independent
# trees, and `seen_paths` dedups within each process. Duplication factor 1.0
# by construction.
#
# Do NOT add "more chains" per scenario to go faster. To parallelise WITHIN a
# scenario you need disjoint SEED ROOTS (EXTRA_SEEDS_JSON), which is what
# _p44_drive_par.sh does -- and that belongs to stage 2, once there is a
# corpus to derive seeds from. Base exploration has no seeds yet.
#
# Legs are deliberately NOT re-run in rounds from scratch either: a second
# round with the same inputs re-walks the same prefix of the same tree and
# writes it again under a new label. Divergence comes from SEEDS (stage 2),
# not from repetition. One leg here = one exploration, run until it drains or
# its budget expires.
# ------------------------------------------------------------------------
#
# usage: _p47_gen_v2.sh [MAX_RUNS] [TIME_BUDGET]
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project

B=/home/dev/project/reports/diaspora/results3/posts_show
V="$B/v2"
RUNS="${1:-200000}"
BUDGET="${2:-36000}"
RUNID="$(date +%m%d%H%M)"
LOG="$B/_p47_gen_v2.log"
ST="$B/_p47_status"

say() { echo "[$(date -Is)] $*" >> "$LOG"; }
corpus() { find "$V" -maxdepth 1 -name 'dump_*.json' | wc -l; }

say "=== P47 stage-1 START (runid $RUNID, 4 scenario legs, MAX_RUNS=$RUNS TIME_BUDGET=${BUDGET}s, corpus $(corpus)) ==="

leg() {
  local v="$1"
  say "leg $v start (corpus $(corpus))"
  # PRIVATE slot namespace -- see _p47_slot.sh for the incident this fixes.
  # NEVER go back to `tools/slot` here: it searches slots 1..N with no notion
  # of reservation, so any N>=1 can take slot 1..3 out from under the
  # conversations_index gate and hold it for the whole TIME_BUDGET.
  P47_SLOTS="${P47_SLOTS:-3}" MAX_RUNS="$RUNS" TIME_BUDGET="$BUDGET" \
    VARIANTS="$v" LABEL_SUFFIX="_v2${RUNID}${v}" \
    "$B/_p47_slot.sh" \
    /home/dev/project/scripts/diaspora-concolic "$V/run_dse.rb" \
    >> "$B/_p47_leg_${v}.log" 2>&1
  say "leg $v done rc=$? : $(grep -E 'drained=' "$B/_p47_leg_${v}.log" | tail -1)"
}

for v in auth_html anon_html auth_json anon_json; do leg "$v" & done

# Status ticker. Wait for a JRuby to actually exist first -- on this script's
# first invocation the loop raced the legs, found nothing, fell through, and
# _p47_status was never written while the drive ran happily for minutes.
# Silence from a status file is indistinguishable from a dead job.
for _ in $(seq 1 60); do
  pgrep -f "$V/run_dse.rb" > /dev/null 2>&1 && break
  sleep 5
done
while pgrep -f "$V/run_dse.rb" > /dev/null 2>&1; do
  echo "$(date -Is) | P47 stage-1 | corpus $(corpus) dumps | legs $(pgrep -cf "$V/run_dse.rb") | load $(cut -d' ' -f1 /proc/loadavg)" > "$ST"
  sleep 60
done
wait

say "=== P47 stage-1 DONE: $(corpus) dumps ==="
for v in auth_html anon_html auth_json anon_json; do
  say "  $v: $(grep -E 'drained=' "$B/_p47_leg_${v}.log" | tail -1)"
done
echo "$(date -Is) | P47 stage-1 DONE: $(corpus) dumps" > "$ST"
