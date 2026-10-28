#!/bin/bash
# C7 DRIVE — resumable stage machine to take notifications_index to the
# project standard: engine `complete: true`, 0 FAIL / 0 NOT-TESTABLE.
#
# Written 2026-09-08 after two failed attempts:
#   * C7R1 — base rounds doubled the corpus for ZERO new coverage
#     (_C7R1_BASE_ROUND_FINDING.md); the coverage pass then ran 20.25h on the
#     doubled input and died in a VM reboot with nothing written.
#   * C7R2 — same corpus as the 50-min historical baseline but MMC=300; ran
#     4h with no result. The checker builds ONE BLOCKING CLAUSE PER RUN for
#     each of ~660 cliques x up to MMC z3 solves
#     (src/concolic_engine/coverage.py:369-405), and the 18 C7A1 demand dumps
#     added 3 NESTED decision vars that join every clique, multiplying each
#     clique's space 8-64x -> far more cliques run to the cap instead of
#     closing out on UNSAT.
#
# THEREFORE: MMC is a SEEDING-THROUGHPUT knob for demand rounds, not a
# correctness knob. `_demand_root.py` dedups the missing set to a few hundred
# roots per variant regardless, so enumerating 300/clique spends the whole
# runtime on items that get discarded. Demand rounds run at MMC=40.
# The FINAL pass is unaffected: if the corpus truly covers a clique, the
# solver returns UNSAT immediately and the cap is never reached.
#
# RESUMABLE: every stage records itself in _c7_drive_state. Re-running the
# script picks up from the last completed stage — safe after a reboot.
# STATUS: one line in _c7_drive_status, refreshed at every transition.
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_c7_drive.log"
STATE="$B/_c7_drive_state"
STATUS="$B/_c7_drive_status"
# MMC_DEMAND (revised 2026-09-09): this is SEEDING THROUGHPUT, not cost.
# At MMC=1 the coverage pass enumerates ONE missing assignment per clique, so
# the seeder gets one target per clique per round — but a clique only leaves
# MISSING when FULLY covered. That is the slowest possible fill rate and is
# what the 9-round plateau (1 821-1 830) actually measured. 72% of the
# residual is REACHABLE (18/25 co-occur, full-corpus test through the engine's
# load path), so the targets exist; we were just asking for one at a time.
MMC_DEMAND="${MMC_DEMAND:-24}"
# MISSING_CAP (coverage_report.py:311): only entries that reach the JSON can be
# aimed at by the demand loop; the default 200 starved it against missing=3426.
# Raising it is SERIALIZATION cost only, not solver cost -- the code comment
# prescribes exactly this for convergence rounds.
MISSING_CAP="${MISSING_CAP:-6000}"
MAX_ROUNDS="${MAX_ROUNDS:-500}"
VARIANTS_ALL="html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain"

touch "$STATE"
say()  { echo "[$(date -Is)] $*" >> "$LOG"; }
mark() { echo "$1" >> "$STATE"; }
done_already() { grep -qxF "$1" "$STATE"; }
status() { echo "$(date -Is) | $*" > "$STATUS"; }

read_summary() {   # $1=key
  python3 - "$B" "$1" <<'PY' 2>/dev/null
import json,sys
try: print(json.load(open(sys.argv[1]+"/coverage_summary.json")).get(sys.argv[2]))
except Exception: print("ERR")
PY
}

say "=== C7 DRIVE start (MMC_DEMAND=$MMC_DEMAND MAX_ROUNDS=$MAX_ROUNDS) ==="
say "corpus: $(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l) dumps"

# ---------------------------------------------------------------- demand loop
prev_missing=""
prev_dumps=""
prev_nodes=""
rises=0
for R in $(seq 1 "$MAX_ROUNDS"); do
  TAG="D${R}"

  if ! done_already "cov:$TAG"; then
    status "round $R: coverage pass (MMC=$MMC_DEMAND), corpus $(ls $B/dump_*.json|wc -l) dumps"
    say "round $R: coverage pass start (SKIP_COMPLETION=1 MMC=$MMC_DEMAND)"
    env SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE="$MMC_DEMAND" \
      MISSING_CAP="${MISSING_CAP:-6000}" PYTHONPATH=src \
      python3 "$B/coverage_report.py" >> "$LOG" 2>&1
    say "round $R: coverage pass rc=$?"
    mark "cov:$TAG"
  fi

  missing=$(read_summary missing_branches)
  nodes=$(read_summary tree_nodes)
  trunc=$(read_summary truncated)
  dumps=$(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l)
  say "ROUND $R RESULT: nodes=$nodes missing=$missing truncated=$trunc dumps=$dumps"
  status "round $R done: missing=$missing nodes=$nodes dumps=$dumps"

  if [ "$missing" = "0" ]; then
    say "MISSING IS ZERO after round $R — demand loop complete"
    mark "demand:complete"; break
  fi
  if [ -n "$prev_missing" ] && [ "$missing" -gt "$prev_missing" ] 2>/dev/null; then
    rises=$((rises+1))
    say "DIVERGENCE: missing rose $prev_missing -> $missing (rise #$rises)"
    if [ "$rises" -ge 4 ]; then
      say "WARNING: missing has risen $rises rounds running (model concern) — CONTINUING per instruction: do not stop until complete"
    fi
  else
    rises=0
  fi
  if [ "$missing" = "$prev_missing" ] && [ -n "$prev_dumps" ] && [ "$dumps" -gt "$prev_dumps" ] 2>/dev/null; then
    say "WARNING: missing unchanged at $missing though the corpus grew $prev_dumps -> $dumps — CONTINUING"
    :
  fi
  prev_missing="$missing"; prev_dumps="$dumps"; prev_nodes="$nodes"
  [ "$R" = "$MAX_ROUNDS" ] && { say "MAX_ROUNDS reached with missing=$missing"; mark "demand:maxrounds"; break; }

  if ! done_already "dse:$TAG"; then
    status "round $R: building demand roots"
    python3 "$B/_demand_root.py" >> "$LOG" 2>&1
    say "round $R: _demand_root.py rc=$?"
    before=$dumps
    for V in $VARIANTS_ALL; do
      F="$B/_demandR_${V}.json"
      [ -s "$F" ] || { say "round $R $V: no seeds"; continue; }
      n=$(python3 -c "import json;print(len(json.load(open('$F'))))" 2>/dev/null)
      status "round $R: DSE $V ($n roots), corpus $(ls $B/dump_*.json|wc -l)"
      say "round $R $V: $n roots"
      /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" \
        EXTRA_SEEDS_JSON="$F" LABEL_SUFFIX="_${TAG}${V:0:3}" \
        MAX_RUNS=600 TIME_BUDGET=360 \
        /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" >> "$LOG" 2>&1
    done
    after=$(find "$B" -maxdepth 1 -name "dump_*.json" | wc -l)
    say "round $R DSE done: $before -> $after dumps (+$((after-before)))"
    if [ "$after" -le "$before" ]; then
      say "WARNING: round $R added no dumps (missing=$missing) — CONTINUING"
    fi
    mark "dse:$TAG"
  fi
done

# ------------------------------------------------------------- full engine
if [ "$missing" = "0" ] && ! done_already "engine:done"; then
  status "FULL ENGINE pass (completion gate ON) — corpus $(ls $B/dump_*.json|wc -l) dumps"
  say "=== FULL ENGINE pass (no SKIP_COMPLETION) ==="
  env MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src \
    python3 "$B/coverage_report.py" >> "$LOG" 2>&1
  say "full engine rc=$?"
  mark "engine:done"
fi
complete=$(read_summary complete)
missing=$(read_summary missing_branches)
nodes=$(read_summary tree_nodes)
say "ENGINE RESULT: complete=$complete missing=$missing nodes=$nodes dumps=$(ls $B/dump_*.json|wc -l)"
status "ENGINE RESULT: complete=$complete missing=$missing nodes=$nodes"

# ------------------------------------------------------------------ audits
if [ "$complete" = "True" ] && ! done_already "audits:done"; then
  status "AUDITS running (_c7_audits.sh)"
  say "=== AUDITS ==="
  bash "$B/_c7_audits.sh" >> "$LOG" 2>&1
  say "audits rc=$?"
  mark "audits:done"
  status "AUDITS done — see _c7_drive.log"
fi

say "=== C7 DRIVE END: complete=$complete missing=$missing ==="
status "DRIVE ENDED: complete=$complete missing=$missing"
