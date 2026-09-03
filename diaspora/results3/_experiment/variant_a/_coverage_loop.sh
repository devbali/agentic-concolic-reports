#!/bin/bash
# gen2 coverage loop (2026-08-19): repeat {check -> seed missing -> targeted
# DSE append round} until missing==0 or the missing set stops changing
# (stalled demands are assumption/honest-stop candidates, never forced).
set -uo pipefail
HERE=/home/dev/project/reports/diaspora/results3/_experiment/variant_a
cd /home/dev/project
LOG="$HERE/_coverage_loop.log"
: > "$LOG"
prev_hash=""
for round in 2 3 4 5 6; do
  # ---- coverage check (writes coverage_summary.json) ----
  MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src python3 "$HERE/coverage_report.py" >> "$LOG" 2>&1
  rc=$?
  missing=$(python3 -c "import json;d=json.load(open('$HERE/coverage_summary.json'));print(len(d['missing']))")
  hash=$(python3 -c "
import json,hashlib
d=json.load(open('$HERE/coverage_summary.json'))
s=sorted(m['node_constraint'] for m in d['missing'])
print(hashlib.sha1('\n'.join(s).encode()).hexdigest())")
  echo "== round $round: missing=$missing hash=$hash" >> "$LOG"
  if [ "$missing" = "0" ]; then echo "LOOP_DONE complete" >> "$LOG"; break; fi
  if [ "$hash" = "$prev_hash" ]; then echo "LOOP_STALLED missing=$missing" >> "$LOG"; break; fi
  prev_hash="$hash"
  # ---- build seeds from missing, run targeted append round ----
  python3 -c "
import json
d=json.load(open('$HERE/coverage_summary.json'))
seeds=[m['concrete_values'] for m in d['missing'] if m.get('concrete_values')]
json.dump(seeds, open('$HERE/_seedloop$round.json','w'))
print('seeds:',len(seeds))" >> "$LOG" 2>&1
  # MAX_RUNS must exceed the seed count (a stall in the first loop version
  # traced to 96 seed dicts under an 80-run cap: the tail dicts never ran).
  nseeds=$(python3 -c "import json;print(len(json.load(open('$HERE/_seedloop$round.json'))))")
  JRUBY_OPTS="-J-Xmx1500m" MAX_RUNS=$((nseeds + 40)) TIME_BUDGET=900 SEEDS_ONLY=1 \
    EXTRA_SEEDS_JSON="$HERE/_seedloop$round.json" LABEL_SUFFIX="_seedloop$round" \
    /home/dev/project/scripts/diaspora-concolic "$HERE/run_dse.rb" >> "$LOG" 2>&1
done
echo "LOOP_EXIT" >> "$LOG"
