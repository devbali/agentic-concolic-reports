#!/bin/bash
# cycle 7 — B-6 (no raise in a returns lambda) + B-7 (cardinality 0/1/many,
# preload predicate follows it) regeneration, end to end, in ONE unit:
#   rounds -> dedup -> [coverage -> demand -> dedup] -> [hand seeds -> dedup ->
#   coverage] -> concrete refresh -> FULL engine report -> final audit sweep.
# heavy is taken (once) inside each coverage/report step; slot (once) per JRuby
# launch. Nothing takes slot then heavy.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project

echo "=== [1] fresh corpus $(date +%H:%M:%S) ==="
find "$B" -maxdepth 1 -name 'dump_*.json' -delete
rm -rf "$B/_dup_dumps"
MAXR=12000 "$B/_cycle6_rounds.sh" > "$B/_regen8.log" 2>&1
grep -E 'runs executed|distinct paths|run errors|dumps:' "$B/_regen8.log" | tail -30
"$B/_cycle6_dedup.sh" 2>&1 | tail -1

M=99
for r in h1 h2 h3 h4 h5; do
  echo "=== [2] coverage before $r $(date +%H:%M:%S) ==="
  "$B/_cycle6_cov.sh" > "$B/_cov8_$r.log" 2>&1
  grep -E 'COMPLETE=|loaded|EXIT=' "$B/_cov8_$r.log"
  M=$(python3 -c "import json;print(json.load(open('$B/coverage_summary.json'))['missing_branches'])")
  echo "missing=$M"
  [ "$M" = "0" ] && { echo COVERAGE_COMPLETE; break; }
  if [ "$r" = "h1" ] || [ "$r" = "h2" ]; then
    python3 "$B/demand_round.py" | tail -2
    SUF=_$r "$B/_cycle6_demand.sh" > "$B/_demand8_$r.log" 2>&1
  else
    python3 "$B/mk_hand_seeds.py" 2>&1 | tail -8
    for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
      [ -f "$B/_hand_$v.json" ] || continue
      echo "=== HAND $v (_$r) $(date +%H:%M:%S) ==="
      MAX_RUNS=6000 TIME_BUDGET=3600 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="_$r" \
        flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
        | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -5
    done
  fi
  "$B/_cycle6_dedup.sh" 2>&1 | tail -1
done

if [ "$M" != "0" ]; then
  echo "STOP: coverage still has $M missing — the gate is not run on an incomplete corpus."
  echo CYCLE7_ABORTED; exit 1
fi

echo "=== [3] concrete refresh $(date +%H:%M:%S) ==="
"$B/_cycle6_concrete.sh" > "$B/_concrete8.log" 2>&1
tail -4 "$B/_concrete8.log"

echo "=== [4] FULL engine report $(date +%H:%M:%S) ==="
"$B/_cycle6_report.sh" > "$B/_final8.log" 2>&1
grep -E 'OVERALL_COMPLETE|COMPLETE=|loaded|EXIT=|peak RSS' "$B/_final8.log"

echo "=== [5] final audit sweep $(date +%H:%M:%S) ==="
"$B/_cycle6_audits3.sh" > "$B/_audits8.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits8.log"
echo CYCLE7_DONE
