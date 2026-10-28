#!/bin/bash
# C7 RESUME DRIVER (2026-09-07) — picks up exactly where _c7_demand_state.md
# §4 left off: the C7-A tier is landed and adjudicated, the engine's last
# coverage-only pass reported 151 nodes / 2 621 missing / TRUNCATED, and the
# C7A1 rooted round only got its html_plain variant in (18 dumps) before the
# session ended.
#
# Order (PAUSED_C7 §"What the demand rounds should do meanwhile"):
#   1. PAGED BASE rounds  — enlarge the observed outcome set first; the corpus
#      is small (4 956 dumps) and the missing enumeration truncated, so base
#      rounds shrink the unobserved corner regardless of the model.
#   2. ROOTED DEMAND round — coverage(MMC) -> _demand_root.py -> replay each
#      rooted seed as a worklist ROOT, all seven variants (the step C7A1
#      started).
#   3. COVERAGE-ONLY measurement — the number that decides whether to iterate.
#
# Every JRuby launch goes through tools/slot (2 slots); the coverage passes
# self-lock on /tmp/concolic-heavy.lock and MUST NOT be wrapped in flock
# (self-deadlock, see _c7_cov_only.sh).
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${TAG:-C7R1}"
LOG="$B/_c7_resume_${TAG}.log"
say() { echo "[$(date -Is)] $*" >> "$LOG"; }
: > "$LOG"
say "RESUME $TAG start; dumps=$(ls $B/dump_*.json | wc -l)"

ALL="html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain"

# ---- 1. paged base rounds -------------------------------------------------
for V in $ALL; do
  before=$(ls $B/dump_*.json | wc -l)
  say "BASE $V start (before=$before)"
  /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" \
    MAX_RUNS=900 TIME_BUDGET=420 LABEL_SUFFIX="_${TAG}b${V:0:3}" \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  say "BASE $V done rc=$? (now=$(ls $B/dump_*.json | wc -l))"
done
say "BASE ROUNDS DONE; dumps=$(ls $B/dump_*.json | wc -l)"

# ---- 2. rooted demand round (all seven variants) --------------------------
say "DEMAND coverage pass start (SKIP_COMPLETION=1 MMC=300)"
env SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=300 PYTHONPATH=src \
  python3 "$B/coverage_report.py" >> "$LOG" 2>&1
say "DEMAND coverage pass done rc=$?"
python3 "$B/_demand_root.py" >> "$LOG" 2>&1
say "demand_root done rc=$?"
for V in $ALL; do
  F="$B/_demandR_${V}.json"
  [ -s "$F" ] || { say "DEMAND $V : no seeds, skipped"; continue; }
  n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
  say "DEMAND $V : $n roots"
  /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" \
    EXTRA_SEEDS_JSON="$F" LABEL_SUFFIX="_${TAG}${V:0:3}" \
    MAX_RUNS=900 TIME_BUDGET=500 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  say "DEMAND $V done rc=$? (now=$(ls $B/dump_*.json | wc -l))"
done
say "DEMAND ROUND DONE; dumps=$(ls $B/dump_*.json | wc -l)"

# ---- 3. the measurement ---------------------------------------------------
say "MEASURE coverage-only start"
env SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src \
  python3 "$B/coverage_report.py" >> "$LOG" 2>&1
say "MEASURE done rc=$?"
python3 - "$B" >> "$LOG" 2>&1 <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + "/coverage_summary.json"))
print("RESUME RESULT: nodes=%s missing=%s truncated=%s runs=%s pcs=%s" % (
    d["tree_nodes"], d["missing_branches"], d["truncated"],
    d["total_runs"], d["total_path_conditions"]))
PY
say "RESUME $TAG ALL DONE"
