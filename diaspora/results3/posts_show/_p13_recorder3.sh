#!/bin/bash
# CLOSING RECORD — watches _night13c.sh (the extraction-free chain). No
# extraction logs are collected because there is no extraction stage.
set +e
B=/home/dev/project/reports/diaspora/results3/posts_show
R="$B/_COMPLETION_20260910.md"
sleep 60
while pgrep -f "_night13c.s[h]" >/dev/null; do sleep 60; done
{
  echo ""
  echo "## §76.9b CLOSING RECORD — the pass / engine / audit stages, verbatim"
  echo ""
  echo "_(appended by \`_p13_recorder3.sh\`. No extraction section: policies are"
  echo "extracted at CLOSURE only and posts_show is not complete.)_"
  echo ""
  for f in _night13.log _p13c.log _covFINAL_OD0911.log _engine_section.log _c7_audits.log; do
    [ -s "$B/$f" ] || continue
    echo "### $f (tail 30)"; echo '```'; tail -30 "$B/$f"; echo '```'; echo ""
  done
} >> "$R"
echo "closing record written $(date -Is)" >> "$B/_p13_recorder.log"
