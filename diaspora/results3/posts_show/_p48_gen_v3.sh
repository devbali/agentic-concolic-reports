#!/usr/bin/env bash
# P48 — posts_show CORPUS REGENERATION, stage 1, take THREE (v3/), 2026-09-25.
#
# Derived from _p47_gen_v2.sh. Read that file's PARALLELISM block first — every
# word of it still applies and none of it is restated here:
#   * prefix-directed DSE is DETERMINISTIC, so N identical chains re-walk ONE
#     tree (measured duplication factor 2.96);
#   * the SCENARIO is the only sound parallel axis at stage 1;
#   * to parallelise WITHIN a scenario you need disjoint seed roots, which is
#     stage 2 (_p44_drive_par.sh), not this script.
#
# ------------------------------------------------------------------------
# WHY A THIRD CORPUS. Bug B-6, found 2026-09-25 by the step-7 cheap checks on
# v2 and validated by the _p48_b6_ctl/_p48_b6_fix differential.
#
# posts_show's `sql_for` ignored `args` on the Relation path, so every
# `relation.find_by(conditions)` note DROPPED the finder's own WHERE:
#
#   real: SELECT "likes".* FROM "likes" WHERE ... AND "likes"."author_id" = ?
#   note: SELECT "likes".* FROM "likes" WHERE ...
#
# from post.rb's like_for/reshare_for and poll.rb's participation_answer. The
# dropped conjunct is `author_id = <the signed-in user>` — a PRINCIPAL
# predicate — so the extracted policy claimed the endpoint discloses EVERY like
# on a post when it discloses only the viewer's own.
#
# Four sibling endpoints have carried this repair since 2026-08-21 ("the
# severed contacts chain"); posts_show lost it, almost certainly in the
# 2026-09-09 Rule-T re-sync that also silently deleted ConcreteSymbolicString
# here. The fix is a BACK-PORT, applied batch-locally by _p48_patch_b6.py.
#
# Notes are baked into dumps at EXPLORATION time — the same property that made
# B-4 unrepairable in place — so the corpus has to be regenerated. v2 is kept,
# not deleted: mixing note generations in one corpus is exactly the B-4
# mistake (handoff §3a).
# ------------------------------------------------------------------------
#
# DIFFERENCES FROM _p47_gen_v2.sh, and why:
#
#  1. Output is v3/, and v3/ carries its OWN copies of run_dse.rb, targets.rb
#     and concolic_targets.rb — the B-6-patched ones. run_dse.rb writes dumps
#     to its own directory, so v2/ is untouched.
#
#  2. P47_SLOTS defaults to 4, not 3, so all FOUR legs run concurrently
#     instead of three-then-one. v2's auth legs had to be restarted mid-drive
#     for the B-2 fix and ended up with staggered budgets; there is no such
#     restart planned here, so a flat four-wide run keeps the legs comparable.
#     4 JRuby x ~1.2 GB ~= 5 GB, against a box with ~44 GB free and the
#     conversations_index gate holding 3 SHARED slots. This namespace is
#     PRIVATE (_p47_slot.sh), so those two pools cannot contend.
#
#  3. STACK_LIMIT is left at its default (50 000) DELIBERATELY. v2 discarded
#     5 924 844 novel frontier entries, which is tempting to "fix" by raising
#     it — but every leg stopped on TIME_BUDGET, not on an exhausted worklist,
#     so the number of paths walked is TIME-bound, not frontier-bound. A bigger
#     frontier would mainly shrink the reported `frontier_entries_dropped`
#     without walking more of the tree, while changing DFS order and making v3
#     non-comparable to v2. Frontier truncation is what stage 2 repairs, by
#     CONSTRUCTING runs from Z3 counterexamples (RUNBOOK Phase 2).
#
# usage: _p48_gen_v3.sh [MAX_RUNS] [TIME_BUDGET]
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project

B=/home/dev/project/reports/diaspora/results3/posts_show
V="$B/v3"
RUNS="${1:-200000}"
BUDGET="${2:-36000}"
RUNID="$(date +%m%d%H%M)"
LOG="$B/_p48_gen_v3.log"
ST="$B/_p48_status"

say() { echo "[$(date -Is)] $*" >> "$LOG"; }
corpus() { find "$V" -maxdepth 1 -name 'dump_*.json' | wc -l; }

# --- preflight: refuse to drive with an unpatched tree ------------------
# The whole point of v3 is the B-6 repair. Driving 10 h with the wrong
# concolic_targets.rb would be silent and would cost a day.
for f in run_dse.rb targets.rb concolic_targets.rb; do
  [ -f "$V/$f" ] || { echo "MISSING $V/$f — run the setup step first" >&2; exit 2; }
done
if ! grep -q 'extra = relation_args_where' "$V/concolic_targets.rb"; then
  echo "REFUSING: $V/concolic_targets.rb is NOT B-6-patched (no relation_args_where fold)" >&2
  exit 2
fi
if [ -n "$(find "$V" -maxdepth 1 -name 'dump_*.json' -print -quit)" ]; then
  echo "REFUSING: $V already holds dumps — move them aside first (never mix note generations)" >&2
  exit 2
fi
echo "preflight OK: $V is B-6-patched and empty"

say "=== P48 stage-1 START (runid $RUNID, 4 scenario legs, MAX_RUNS=$RUNS TIME_BUDGET=${BUDGET}s, corpus $(corpus)) ==="
say "    B-6 back-port verified present in $V/concolic_targets.rb"

leg() {
  local v="$1"
  say "leg $v start (corpus $(corpus))"
  # PRIVATE slot namespace — see _p47_slot.sh for the incident this fixes.
  # NEVER go back to `tools/slot`: it searches slots 1..N with no notion of
  # reservation, so any N can take slots 1-3 out from under the
  # conversations_index gate and hold them for the whole TIME_BUDGET.
  P47_SLOTS="${P47_SLOTS:-4}" MAX_RUNS="$RUNS" TIME_BUDGET="$BUDGET" \
    VARIANTS="$v" LABEL_SUFFIX="_v3${RUNID}${v}" \
    "$B/_p47_slot.sh" \
    /home/dev/project/scripts/diaspora-concolic "$V/run_dse.rb" \
    >> "$B/_p48_leg_${v}.log" 2>&1
  say "leg $v done rc=$? : $(grep -E 'drained=' "$B/_p48_leg_${v}.log" | tail -1)"
}

for v in auth_html anon_html auth_json anon_json; do leg "$v" & done

# Status ticker. Wait for a JRuby to exist first — on _p47_gen_v2.sh's first
# invocation this loop raced the legs, found nothing, fell through, and the
# status file was never written while the drive ran fine for minutes. Silence
# from a status file is indistinguishable from a dead job.
for _ in $(seq 1 60); do
  pgrep -f "$V/run_dse.rb" > /dev/null 2>&1 && break
  sleep 5
done
while pgrep -f "$V/run_dse.rb" > /dev/null 2>&1; do
  echo "$(date -Is) | P48 stage-1 | corpus $(corpus) dumps | legs $(pgrep -cf "$V/run_dse.rb") | load $(cut -d' ' -f1 /proc/loadavg)" > "$ST"
  sleep 60
done
wait

say "=== P48 stage-1 DONE: $(corpus) dumps ==="
for v in auth_html anon_html auth_json anon_json; do
  say "  $v: $(grep -E 'drained=' "$B/_p48_leg_${v}.log" | tail -1)"
done
echo "$(date -Is) | P48 stage-1 DONE: $(corpus) dumps" > "$ST"
