#!/bin/bash
# CLOSING RECORD (corrected: watches _night13b.sh, the chain that is actually
# running, and also waits for the long extraction). Appends §76.9b when both
# have ended, so the numbers reach the record with or without an agent.
set +e
B=/home/dev/project/reports/diaspora/results3/posts_show
R="$B/_COMPLETION_20260910.md"
while pgrep -f "_night13b.s[h]" >/dev/null || pgrep -f "_extract_posts_show_streamin[g].py" >/dev/null; do sleep 60; done
{
  echo ""
  echo "## §76.9b CLOSING RECORD — every stage's own verdict lines, verbatim"
  echo ""
  echo "_(appended by \`_p13_recorder2.sh\` when the night chain and the"
  echo "extraction both ended.)_"
  echo ""
  for f in _night13.log _p13c.log _p13d.log _conj_price.log _shim_run_20260911.log \
           _covFINAL_OD0911.log _engine_section.log _policy_numbers.log; do
    [ -s "$B/$f" ] || continue
    echo "### $f (tail 30)"; echo '```'; tail -30 "$B/$f"; echo '```'; echo ""
  done
  Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
  for f in _extract_posts_show_NOSUB_20260911.log _extract_posts_show_SUBSUME_20260911.log; do
    [ -s "$Q/$f" ] || continue
    echo "### $f (tail 25)"; echo '```'; tail -25 "$Q/$f"; echo '```'; echo ""
  done
} >> "$R"
echo "closing record written $(date -Is)" >> "$B/_p13_recorder.log"
