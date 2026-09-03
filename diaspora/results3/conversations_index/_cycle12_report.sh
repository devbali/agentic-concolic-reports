#!/bin/bash
# cycle 12 — report-only re-run; c11 again captured a PRE-FIX cardinality audit.
# PRE-FIX cardinality_consistency output (engine runs audits first, at ~04:36;
# the corrected audit landed 04:39:44), so the single blocking item was a stale
# TOOL read, not a corpus defect. Heavy taken ONCE, outermost, inside this unit.
# C10-8 lesson: the acquired marker is echoed to the SAME log progress is read
# from, so this pass cannot be misdiagnosed as queued.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
echo "=== pre-flight: cardinality audit on the unchanged corpus ==="
PYTHONPATH=/home/dev/project/src python3 src/queries_from_runs/audits/cardinality_consistency_audit.py "$B" | tail -2
echo "preflight EXIT=${PIPESTATUS[0]}"
echo "[heavy] waiting $(date +%H:%M:%S)"
flock /tmp/concolic-heavy.lock bash -c '
B=/home/dev/project/reports/diaspora/results3/conversations_index
echo "[heavy] acquired $(date +%H:%M:%S)"; free -m | head -2
MAX_MISSING_PER_CLIQUE=60 PYTHONPATH=/home/dev/project/src \
  python3 $B/coverage_report.py' 2>&1 | tee "$B/_final14.log"
echo "[heavy] released $(date +%H:%M:%S)"
echo "=== verdict ==="
grep -E 'OVERALL_COMPLETE|^COMPLETE=|GENUINE=' "$B/_final14.log"
python3 -c "
import json
d=json.load(open('$B/coverage_summary.json'))
c=d['completion']
print('completion.complete =',c['complete'])
print('blocking =',c['blocking'])
print('audits  =',[(a['name'],a['green']) for a in c['audits']])
print('shims   =',c['shim_verdict_counts'])
print('assumps =',c['assumptions']['verdict_counts'],'failures',len(c['assumptions']['failures']))
"
echo CYCLE12_DONE
