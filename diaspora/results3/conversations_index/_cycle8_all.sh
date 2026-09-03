#!/bin/bash
# cycle 8 — B-8 (a falsy return still publishes its statement) + M-7 (the
# preload predicate follows the DISTINCT FK count) on top of cycle 7's B-6/B-7.
# rounds -> dedup -> [verified coverage -> demand|hand -> dedup] -> concrete ->
# FULL report -> final audits. Every coverage pass is judged by its OWN
# COMPLETE= verdict line, never by re-reading coverage_summary.json.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project

echo "=== [1] fresh corpus $(date +%H:%M:%S) ==="
find "$B" -maxdepth 1 -name 'dump_*.json' -delete
rm -rf "$B/_dup_dumps"
MAXR=12000 "$B/_cycle6_rounds.sh" > "$B/_regen10.log" 2>&1
grep -E 'distinct paths|run errors|dumps:' "$B/_regen10.log" | tail -20
"$B/_cycle6_dedup.sh" 2>&1 | tail -1

M=99
for r in k1 k2 k3 k4 k5 k6 k7; do
  echo "=== [2] coverage before $r $(date +%H:%M:%S) ==="
  "$B/_cycle6_cov.sh" > "$B/_cov10_$r.log" 2>&1
  line=$(grep -E '^COMPLETE=' "$B/_cov10_$r.log" || true)
  if [ -z "$line" ]; then
    echo "COVERAGE PASS PRODUCED NO VERDICT — its own output:"; tail -20 "$B/_cov10_$r.log"
    echo CYCLE8_ABORTED; exit 1
  fi
  echo "$line"; grep -E 'loaded' "$B/_cov10_$r.log"
  M=$(echo "$line" | sed -E 's/.*MISSING=([0-9]+).*/\1/'); echo "missing=$M"
  [ "$M" = "0" ] && { echo COVERAGE_COMPLETE; break; }
  if [ "$r" = "k1" ] || [ "$r" = "k2" ] || [ "$r" = "k3" ]; then
    python3 "$B/demand_round.py" | tail -2
    SUF=_$r "$B/_cycle6_demand.sh" > "$B/_demand10_$r.log" 2>&1
  else
    python3 "$B/mk_hand_seeds.py" 2>&1 | tail -6
    for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
      [ -f "$B/_hand_$v.json" ] || continue
      echo "=== HAND $v (_$r) $(date +%H:%M:%S) ==="
      MAX_RUNS=6000 TIME_BUDGET=3600 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="_$r" \
        flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
        | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -3
    done
  fi
  "$B/_cycle6_dedup.sh" 2>&1 | tail -1
done

[ "$M" = "0" ] || { echo "STOP: $M missing — gate not run on an incomplete corpus."; echo CYCLE8_ABORTED; exit 1; }

echo "=== [3] concrete refresh $(date +%H:%M:%S) ==="
"$B/_cycle6_concrete.sh" > "$B/_concrete10.log" 2>&1; tail -3 "$B/_concrete10.log"
echo "=== [4] FULL engine report $(date +%H:%M:%S) ==="
"$B/_cycle6_report.sh" > "$B/_final10.log" 2>&1
grep -E 'OVERALL_COMPLETE|^COMPLETE=|loaded|EXIT=|peak RSS' "$B/_final10.log"
echo "=== [5] final audit sweep $(date +%H:%M:%S) ==="
"$B/_cycle6_audits3.sh" > "$B/_audits10.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits10.log"
echo "=== [6] noteless audit $(date +%H:%M:%S) ==="
PYTHONPATH=/home/dev/project/src python3 src/queries_from_runs/audits/noteless_call_audit.py "$B" > "$B/_a10_noteless.out" 2>&1
echo "noteless EXIT=$?"; tail -4 "$B/_a10_noteless.out"
echo CYCLE8_DONE
