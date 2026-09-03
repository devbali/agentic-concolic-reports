#!/bin/bash
# cycle 7 (resume) — the corpus is already regenerated; run the coverage/demand
# loop, then concrete -> full report -> audits.
# Every coverage pass is VERIFIED BY ITS OWN OUTPUT (the report's COMPLETE=
# line), never by re-reading coverage_summary.json — reading a summary that a
# crashed/killed pass never rewrote is exactly how cycle 5 lost three rounds.
set -u
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/conversations_index
cd /home/dev/project

M=99
for r in h1 h2 h3 h4 h5 h6; do
  echo "=== coverage before $r $(date +%H:%M:%S) ==="
  "$B/_cycle6_cov.sh" > "$B/_cov9_$r.log" 2>&1
  line=$(grep -E '^COMPLETE=' "$B/_cov9_$r.log" || true)
  if [ -z "$line" ]; then
    echo "COVERAGE PASS PRODUCED NO VERDICT (crashed or killed) — its own output:"
    tail -20 "$B/_cov9_$r.log"
    echo CYCLE7R_ABORTED; exit 1
  fi
  echo "$line"; grep -E 'loaded|peak RSS' "$B/_cov9_$r.log"
  M=$(echo "$line" | sed -E 's/.*MISSING=([0-9]+).*/\1/')
  echo "missing=$M"
  [ "$M" = "0" ] && { echo COVERAGE_COMPLETE; break; }
  if [ "$r" = "h1" ] || [ "$r" = "h2" ]; then
    python3 "$B/demand_round.py" | tail -2
    SUF=_$r "$B/_cycle6_demand.sh" > "$B/_demand9_$r.log" 2>&1
    grep -E 'run errors' "$B/_demand9_$r.log" | tail -6
  else
    python3 "$B/mk_hand_seeds.py" 2>&1 | tail -8
    for v in html_plain html_withcid json_plain json_withcid mobile_plain mobile_withcid; do
      [ -f "$B/_hand_$v.json" ] || continue
      echo "=== HAND $v (_$r) $(date +%H:%M:%S) ==="
      MAX_RUNS=6000 TIME_BUDGET=3600 VARIANTS=$v EXTRA_SEEDS_JSON="$B/_hand_$v.json" LABEL_SUFFIX="_$r" \
        flock /tmp/concolic-slot.lock scripts/diaspora-concolic "$B/run_dse.rb" 2>&1 \
        | grep -viE 'deprecat|fog\]|Ignoring activerecord|Top level ::' | tail -4
    done
  fi
  "$B/_cycle6_dedup.sh" 2>&1 | tail -1
done

[ "$M" = "0" ] || { echo "STOP: $M missing — the gate is not run on an incomplete corpus."; echo CYCLE7R_ABORTED; exit 1; }

echo "=== concrete refresh $(date +%H:%M:%S) ==="
"$B/_cycle6_concrete.sh" > "$B/_concrete9.log" 2>&1; tail -3 "$B/_concrete9.log"
echo "=== FULL engine report $(date +%H:%M:%S) ==="
"$B/_cycle6_report.sh" > "$B/_final9.log" 2>&1
grep -E 'OVERALL_COMPLETE|^COMPLETE=|loaded|EXIT=|peak RSS' "$B/_final9.log"
echo "=== final audit sweep $(date +%H:%M:%S) ==="
"$B/_cycle6_audits3.sh" > "$B/_audits9.log" 2>&1
grep -E 'EXIT=|RESULT' "$B/_audits9.log"
echo CYCLE7R_DONE
