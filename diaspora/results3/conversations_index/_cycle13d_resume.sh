#!/bin/bash
# cycle 13b — resume from the coverage step after the two GATE fixes (A3-8).
# C-5 (write follows dirty state), the layout pin's data access (NM-5) + the
# `sum` target, C-6 (conversation_id[] -> IN), C-7 (invalid page), C-8 (js +
# undeclared-format family). 10 variants now, not 6.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project
VARS="html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid js_plain js_withcid xml_plain xml_withcid"
"$B/_cycle6_dedup.sh" 2>&1 | tail -1
M=99
for r in n1 n2 n3 n4 n5 n6 n7 n8; do
  echo "=== coverage $r $(date +%H:%M:%S) ==="
  MMPC=60 "$B/_cycle6_cov.sh" > "$B/_cov13b_$r.log" 2>&1
  line=$(grep -E '^COMPLETE=' "$B/_cov13b_$r.log" || true)
  if [ -z "$line" ]; then echo "NO VERDICT:"; tail -25 "$B/_cov13b_$r.log"; echo CYCLE13B_ABORTED; exit 1; fi
  echo "$line"; grep -E 'loaded' "$B/_cov13b_$r.log"
  M=$(echo "$line" | sed -E 's/.*MISSING=([0-9]+).*/\1/'); echo "missing=$M"
  [ "$M" = "0" ] && { echo COVERAGE_COMPLETE; break; }
  python3 "$B/mk_hand_seeds2.py" 2>&1 | grep -E 'hand roots|no donor|skip'
  for v in $VARS; do
    [ -f "$B/_hand_$v.json" ] || continue
    # (i) REPLAY every hand root exactly once — SEEDS_ONLY bypasses the
    #     state/path dedup and does no flip expansion: 27 roots -> 27 runs,
    #     seconds, each landing its combination if its seeds are right
    #     (A3-13: 12 -> 18 of 32 assignments in ONE such replay).
    SEEDS_ONLY=1 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="_${r}r" \
      flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 | grep -E 'runs executed' | tr -s ' '
    # (ii) a SHORT expansion from the same roots for the neighbours
    MAX_RUNS=800 TIME_BUDGET=240 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="_${r}x" \
      flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 | grep -E 'distinct paths' | tr -s ' '
  done
  "$B/_cycle6_dedup.sh" 2>&1 | tail -1
done
[ "$M" = "0" ] || { echo "STOP: $M missing."; echo CYCLE13B_ABORTED; exit 1; }
echo "=== concrete refresh (FIXED manifest: INSTR-1/2/3) $(date +%H:%M:%S) ==="
"$B/_cycle6_concrete.sh" > "$B/_concrete13b.log" 2>&1; tail -3 "$B/_concrete13.log"
echo "=== FULL engine report $(date +%H:%M:%S) ==="
echo "[heavy] waiting $(date +%H:%M:%S)"
flock /tmp/concolic-heavy.lock bash -c '
echo "[heavy] acquired $(date +%H:%M:%S)"
MAX_MISSING_PER_CLIQUE=60 PYTHONPATH=/home/dev/project/src \
  python3 /home/dev/project/reports/diaspora/results3/conversations_index/coverage_report.py' \
  2>&1 | tee "$B/_final15b.log" | grep -E 'OVERALL_COMPLETE|^COMPLETE=|GENUINE='
python3 -c "
import json;d=json.load(open('$B/coverage_summary.json'));c=d['completion']
print('completion.complete =',c['complete']); print('blocking =',c['blocking'])
print('audits =',[(a['name'],a['green']) for a in c['audits']])
print('shims =',c['shim_verdict_counts']); print('assumps =',c['assumptions']['verdict_counts'])"
echo "=== eight audits $(date +%H:%M:%S) ==="
"$B/_cycle10_audits8.sh" > "$B/_audits13b.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits13b.log"
echo "=== lint WITH runs (H6) $(date +%H:%M:%S) ==="
PYTHONPATH=/home/dev/project/src python3 reports/diaspora/tools/hardening_lint.py "$B" \
  --runs "$B"/concrete_run*.json --sample 0 > "$B/_a13b_lint.out" 2>&1
echo "lint EXIT=$?"; tail -6 "$B/_a13b_lint.out"
echo CYCLE13B_DONE
