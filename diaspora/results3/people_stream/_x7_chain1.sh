#!/bin/bash
# Chain: identity rooted round (running) -> demand round -> coverage pass.
# Every step caged (JRuby 2G, pass 1G) per the coordinator's 2026-09-11 rule.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/people_stream
cd /home/dev/project
while pgrep -f "people_stream/run_dse.rb" > /dev/null; do sleep 10; done
# one roots file per scenario -> merge (SEEDS_ONLY replays roots in EVERY
# scenario, and a root from another scenario simply produces a duplicate path)
python3 - <<'PY'
import glob, json, os
B="/home/dev/project/reports/diaspora/results3/people_stream"
roots=[]
for f in sorted(glob.glob(os.path.join(B,"_demandR_*.json"))):
    roots.extend(json.load(open(f)))
json.dump(roots, open(os.path.join(B,"_demandR_all.json"),"w"))
print("merged %d demand roots" % len(roots))
PY
$B/_x7_rooted_round.sh $B/_demandR_all.json "_DMR1" 2000 1800
while pgrep -f "people_stream/run_dse.rb" > /dev/null; do sleep 10; done
$B/_caged 1G env SKIP_COMPLETION=1 PYTHONPATH=/home/dev/project/src \
  /home/dev/project/venvs/queries_from_runs/bin/python $B/coverage_report.py > $B/_cov_round2.log 2>&1
echo "[$(date -Is)] chain1 done"
tail -12 $B/_cov_round2.log
