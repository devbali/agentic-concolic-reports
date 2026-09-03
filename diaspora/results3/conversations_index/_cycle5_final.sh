#!/bin/bash
# concrete refresh (real app, no mocks) then the FULL engine report.
set -u
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
echo "--- concrete ---"
"$B/_cycle5_concrete.sh" > "$B/_concrete5.log" 2>&1
tail -12 "$B/_concrete5.log"
echo "--- full report (coverage + completion gate) ---"
"$B/_cycle5_report.sh" > "$B/_final5.log" 2>&1
grep -E 'COMPLETE=|loaded|EXIT=|heavy' "$B/_final5.log"
echo FINAL5_DONE
