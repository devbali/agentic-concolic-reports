#!/bin/bash
# Chain 2: (tree round TR1 already queued) -> demand round DMR2 -> coverage pass.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/people_stream
cd /home/dev/project
while pgrep -f "people_stream/run_dse.rb" > /dev/null || pgrep -f "_x7_rooted_round.sh" > /dev/null; do sleep 15; done
python3 - <<'PY'
import glob, json, os
B="/home/dev/project/reports/diaspora/results3/people_stream"
roots=[]
for f in sorted(glob.glob(os.path.join(B,"_demandR_*.json"))):
    if f.endswith("_all.json"): continue
    roots.extend(json.load(open(f)))
json.dump(roots, open(os.path.join(B,"_demandR_all.json"),"w"))
print("merged %d demand roots" % len(roots))
PY
$B/_x7_rooted_round.sh $B/_demandR_all.json "_DMR2" 2000 1800
while pgrep -f "people_stream/run_dse.rb" > /dev/null; do sleep 15; done
$B/_caged 1G env SKIP_COMPLETION=1 PYTHONPATH=/home/dev/project/src \
  /home/dev/project/venvs/queries_from_runs/bin/python $B/coverage_report.py > $B/_cov_round3.log 2>&1
echo "[$(date -Is)] chain2 done"
grep -E "^COMPLETE=|^DEMAND_SETS=|TREE-MISSING|loaded |assumptions" $B/_cov_round3.log
