#!/bin/bash
# C7 RESUME 2 (2026-09-08) — restart after the VM reboot killed the 20.25h
# coverage pass, on the ORIGINAL 4 956-dump corpus.
#
# The 4 938 base-round dumps are archived in _archive_c7r1base_dumps/ — they
# added ZERO new decision variables and ~8 new path signatures (see
# _C7R1_BASE_ROUND_FINDING.md), while the checker builds ONE BLOCKING CLAUSE
# PER RUN for every one of ~660 cliques × up to 300 z3 solves
# (src/concolic_engine/coverage.py:369-405). Doubling the runs squared the
# per-solve cost for no information. Do NOT re-add them.
#
# Steps (base rounds deliberately SKIPPED):
#   1. coverage pass MMC=300 -> _demand_root.py -> 7 rooted DSE variants
#   2. coverage-only measurement MMC=4 -> the number that decides the next round
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${TAG:-C7R2}"
LOG="$B/_c7_resume2_${TAG}.log"
say() { echo "[$(date -Is)] $*" >> "$LOG"; }
: > "$LOG"
say "RESUME2 $TAG start; dumps=$(ls $B/dump_*.json | wc -l)"

say "DEMAND coverage pass start (SKIP_COMPLETION=1 MMC=300)"
env SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=300 PYTHONPATH=src \
  python3 "$B/coverage_report.py" >> "$LOG" 2>&1
say "DEMAND coverage pass done rc=$?"
python3 - "$B" >> "$LOG" 2>&1 <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + "/coverage_summary.json"))
print("COVERAGE PASS RESULT: nodes=%s missing=%s truncated=%s runs=%s" % (
    d["tree_nodes"], d["missing_branches"], d["truncated"], d["total_runs"]))
PY
python3 "$B/_demand_root.py" >> "$LOG" 2>&1
say "demand_root done rc=$?"

for V in html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain; do
  F="$B/_demandR_${V}.json"
  [ -s "$F" ] || { say "DEMAND $V : no seeds, skipped"; continue; }
  n=$(python3 -c "import json;print(len(json.load(open('$F'))))")
  say "DEMAND $V : $n roots"
  /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" \
    EXTRA_SEEDS_JSON="$F" LABEL_SUFFIX="_${TAG}${V:0:3}" \
    MAX_RUNS=900 TIME_BUDGET=500 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
  say "DEMAND $V done rc=$? (dumps=$(ls $B/dump_*.json | wc -l))"
done
say "DEMAND ROUND DONE; dumps=$(ls $B/dump_*.json | wc -l)"

say "MEASURE coverage-only start (MMC=4)"
env SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src \
  python3 "$B/coverage_report.py" >> "$LOG" 2>&1
say "MEASURE done rc=$?"
python3 - "$B" >> "$LOG" 2>&1 <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + "/coverage_summary.json"))
print("RESUME2 RESULT: nodes=%s missing=%s truncated=%s runs=%s pcs=%s" % (
    d["tree_nodes"], d["missing_branches"], d["truncated"],
    d["total_runs"], d["total_path_conditions"]))
PY
say "RESUME2 $TAG ALL DONE"
