#!/bin/bash
# INSURANCE (the report-recovery lesson): if this agent is killed mid-night,
# the verdict lines still reach the record. Waits for the night chain to end,
# then appends §76.9 — every stage's own printed verdict, verbatim.
set +e
B=/home/dev/project/reports/diaspora/results3/posts_show
R="$B/_COMPLETION_20260910.md"
while ! grep -q "=== NIGHT 13 DONE ===" "$B/_night13.log" 2>/dev/null; do
  pgrep -f "_night1[3].sh" >/dev/null || { sleep 30; pgrep -f "_night1[3].sh" >/dev/null || break; }
  sleep 60
done
{
  echo ""
  echo "## §76.9 NIGHT-13 STAGE VERDICTS, appended by \`_p13_recorder.sh\`"
  echo ""
  echo "_(This section is written by a detached recorder so the numbers reach the"
  echo "record whether or not an agent is watching. Every line below is copied"
  echo "from the stage's own log.)_"
  echo ""
  echo '```'
  cat "$B/_night13.log"
  echo '```'
  echo ""
  for f in _part_decomp.log _part_report.log _gc_realise_OD0911.log _unev_why.log \
           _matched_ctx_OF0911B.log _covFINAL_OD0911.log _p13d.log; do
    [ -s "$B/$f" ] || continue
    echo "### $f (tail)"
    echo '```'
    tail -25 "$B/$f"
    echo '```'
    echo ""
  done
} >> "$R"
echo "recorded $(date -Is)" >> "$B/_p13_recorder.log"
