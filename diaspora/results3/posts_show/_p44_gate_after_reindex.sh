#!/bin/bash
# P44 -- fire the gate on UNION2 the moment the reindex lands, against the
# LATEST completed sustain round at that moment (not a fixed round), so the
# comparison is against a round the current corpus already reflects.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
L="$B/_p44_gate_postidx.log"
say(){ echo "[$(date -Is)] $*" >> "$L"; }
: > "$L"
say "waiting for _p44_reindex_UNION2.log to say REINDEX-DONE"
w=0
while ! grep -q "REINDEX-DONE UNION2" "$B/_p44_reindex_UNION2.log" 2>/dev/null; do
  grep -q "REINDEX-FAILED" "$B/_p44_reindex_UNION2.log" 2>/dev/null && { say "ABORT: reindex failed"; exit 9; }
  sleep 30; w=$((w+30))
  [ "$w" -gt 10800 ] && { say "ABORT: reindex did not land in 3h"; exit 9; }
done
[ -s "$B/_p44_index_UNION2.pkl" ] || { say "ABORT: no UNION2.pkl despite DONE marker"; exit 9; }
T=$(ls -t "$B"/_p44_done_P44R* 2>/dev/null | head -1 | sed 's#.*_p44_done_##')
[ -z "$T" ] && { say "ABORT: no completed round found"; exit 9; }
say "reindex landed; gating against latest completed round $T"

if [ ! -s "$B/_p44_explain_${T}.json" ]; then
  PYTHONPATH=/home/dev/project/src P15_TAG="$T" P15_SET="$T" \
    P15_GAPS="$B/_p44_gaps_${T}.json" P15_MANIFEST="$B/_p15_manifest_${T}.json" \
    P15_OUT="$B/_p44_explain_${T}.json" \
    python3 -u "$B/_p15_explain.py" >> "$L" 2>&1
fi

PYTHONPATH=/home/dev/project/src P44_INDEX="$B/_p44_index_UNION2.pkl" \
  python3 -u "$B/_p44_gate_build.py" \
  "$B/_p44_gaps_${T}.json" "$B/_p44_explain_${T}.json" \
  "$B/_p44_gaps_GCTRL_${T}_idx2.json" "$B/_p44_gate_join_${T}_idx2.json" >> "$L" 2>&1
[ -s "$B/_p44_gaps_GCTRL_${T}_idx2.json" ] || { say "ABORT: gate_build produced nothing"; exit 9; }

P44_INDEX="$B/_p44_index_UNION2.pkl" P44_PARTS="$B/_p44_parts_${T}.json" \
  bash "$B/_p44_construct.sh" "GCTRL_${T}_idx2" "$B/_p44_gaps_GCTRL_${T}_idx2.json" >> "$L" 2>&1

bash "$B/_p44_drive_par.sh" "GCTRL_${T}_idx2" "GCTRL_${T}_idx2" 200 4 >> "$L" 2>&1
grep -q "PAR-DRIVE-DONE GCTRL_${T}_idx2\$" "$B/_p44_drive_GCTRL_${T}_idx2.log" \
  || { say "ABORT: gate drive did not finish"; exit 9; }

PYTHONPATH=/home/dev/project/src P15_TAG="GCTRL_${T}_idx2" P15_SET="GCTRL_${T}_idx2" \
  P15_GAPS="$B/_p44_gaps_GCTRL_${T}_idx2.json" P15_MANIFEST="$B/_p15_manifest_GCTRL_${T}_idx2.json" \
  P15_OUT="$B/_p44_explain_GCTRL_${T}_idx2.json" \
  python3 -u "$B/_p15_explain.py" >> "$L" 2>&1

PYTHONPATH=/home/dev/project/src \
  P44_GATE_JOIN="$B/_p44_gate_join_${T}_idx2.json" \
  P44_GATE_MISS="$B/_p44_gaps_${T}.json" \
  P44_GATE_GCTRL="$B/_p44_gaps_GCTRL_${T}_idx2.json" \
  P44_GATE_EXPLAIN="$B/_p44_explain_GCTRL_${T}_idx2.json" \
  P44_GATE_OUT="$B/_p44_gate_verdicts_${T}_idx2.json" \
  python3 -u "$B/_p44_gate_verdict.py" >> "$L" 2>&1
say "P44-GATE-POSTIDX-DONE $T $(grep 'POSITIVE CONTROL GREEN' "$L" | tail -1)"
