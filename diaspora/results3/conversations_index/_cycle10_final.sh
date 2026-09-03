#!/bin/bash
# cycle 10 — FINAL: full engine report (heavy taken ONCE, outermost, inside the
# systemd unit) + the eight checks. No DSE, so no slot lock is taken here; the
# gate's own probes take it per JRuby launch.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
echo "=== FULL engine report $(date +%H:%M:%S) ==="
echo "[heavy] waiting $(date +%H:%M:%S)"
flock /tmp/concolic-heavy.lock bash -c '
echo "[heavy] acquired $(date +%H:%M:%S)"; free -m | head -2
MAX_MISSING_PER_CLIQUE=60 PYTHONPATH=/home/dev/project/src \
  python3 /home/dev/project/reports/diaspora/results3/conversations_index/coverage_report.py' \
  > "$B/_final12.log" 2>&1
echo "report EXIT=$?"
echo "[heavy] released $(date +%H:%M:%S)"
grep -E 'OVERALL_COMPLETE|^COMPLETE=|loaded|peak RSS|complete|PASS|FAIL|RED|NO-TEST' "$B/_final12.log" | tail -30
echo "=== audit sweep $(date +%H:%M:%S) ==="
"$B/_cycle6_audits3.sh" > "$B/_audits12.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits12.log"
echo "=== hardening_lint FULL CORPUS (H4 needs every dump, not a sample) ==="
PYTHONPATH=/home/dev/project/src python3 reports/diaspora/tools/hardening_lint.py "$B" --sample 0 \
  > "$B/_a12_lint_full.out" 2>&1
echo "hardening_lint(full) EXIT=$?"; tail -12 "$B/_a12_lint_full.out"
echo "=== cardinality_consistency $(date +%H:%M:%S) ==="
PYTHONPATH=/home/dev/project/src python3 src/queries_from_runs/audits/cardinality_consistency_audit.py "$B" \
  > "$B/_a12_cardinality.out" 2>&1
echo "cardinality EXIT=$?"; head -8 "$B/_a12_cardinality.out"
echo CYCLE10_DONE
