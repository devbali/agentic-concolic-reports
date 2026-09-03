#!/bin/bash
# cycle 9 — close the residue with mk_hand_seeds2 (best-partial dump + the
# checker's own Z3 model), then concrete -> FULL report -> audits.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
M=99
for r in m1 m2 m3 m4; do
  echo "=== hand seeds ($r) $(date +%H:%M:%S) ==="
  python3 "$B/mk_hand_seeds2.py" 2>&1 | tail -10
  for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
    [ -f "$B/_hand_$v.json" ] || continue
    echo "=== HAND $v (_$r) $(date +%H:%M:%S) ==="
    MAX_RUNS=6000 TIME_BUDGET=3600 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="_$r" \
      flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
      | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -3
  done
  "$B/_cycle6_dedup.sh" 2>&1 | tail -1
  echo "=== coverage after $r $(date +%H:%M:%S) ==="
  MMPC=60 "$B/_cycle6_cov.sh" > "$B/_cov11_$r.log" 2>&1
  line=$(grep -E '^COMPLETE=' "$B/_cov11_$r.log" || true)
  if [ -z "$line" ]; then
    echo "COVERAGE PASS PRODUCED NO VERDICT:"; tail -20 "$B/_cov11_$r.log"; echo CYCLE9_ABORTED; exit 1
  fi
  echo "$line"; grep -E 'loaded' "$B/_cov11_$r.log"
  M=$(echo "$line" | sed -E 's/.*MISSING=([0-9]+).*/\1/'); echo "missing=$M"
  [ "$M" = "0" ] && { echo COVERAGE_COMPLETE; break; }
done
[ "$M" = "0" ] || { echo "STOP: $M missing."; echo CYCLE9_ABORTED; exit 1; }
echo "=== concrete refresh $(date +%H:%M:%S) ==="
"$B/_cycle6_concrete.sh" > "$B/_concrete11.log" 2>&1; tail -3 "$B/_concrete11.log"
echo "=== FULL engine report $(date +%H:%M:%S) ==="
"$B/_cycle6_report.sh" > "$B/_final11.log" 2>&1
grep -E 'OVERALL_COMPLETE|^COMPLETE=|loaded|EXIT=|peak RSS' "$B/_final11.log"
echo "=== final audit sweep $(date +%H:%M:%S) ==="
"$B/_cycle6_audits3.sh" > "$B/_audits11.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits11.log"
echo "=== noteless $(date +%H:%M:%S) ==="
PYTHONPATH=/home/dev/project/src python3 src/queries_from_runs/audits/noteless_call_audit.py "$B" > "$B/_a11_noteless.out" 2>&1
echo "noteless EXIT=$?"; tail -3 "$B/_a11_noteless.out"
echo CYCLE9_DONE
