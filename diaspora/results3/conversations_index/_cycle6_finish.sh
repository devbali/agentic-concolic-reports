#!/bin/bash
# cycle 6 — everything after coverage reaches 0 missing:
#   concrete refresh (targets changed) -> FULL engine report (coverage +
#   completion gate) -> final audit sweep with the cycle-6 gate list.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
until grep -q 'HAND6_DONE' "$B/_hand7.log" 2>/dev/null; do sleep 30; done
M=$(python3 -c "import json;print(json.load(open('$B/coverage_summary.json'))['missing_branches'])")
echo "hand rounds finished $(date +%H:%M:%S); missing=$M"
if [ "$M" != "0" ]; then
  echo "STOP: coverage still has $M missing — not running the gate on an incomplete corpus."
  echo FINISH6_ABORTED
  exit 1
fi
echo "--- concrete refresh $(date +%H:%M:%S) ---"
"$B/_cycle6_concrete.sh" > "$B/_concrete7.log" 2>&1
tail -4 "$B/_concrete7.log"
echo "--- FULL engine report $(date +%H:%M:%S) ---"
"$B/_cycle6_report.sh" > "$B/_final7.log" 2>&1
grep -E 'OVERALL_COMPLETE|COMPLETE=|loaded|EXIT=|peak RSS' "$B/_final7.log"
echo "--- final audit sweep $(date +%H:%M:%S) ---"
"$B/_cycle6_audits3.sh" > "$B/_audits7.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits7.log"
echo FINISH6_DONE
