#!/bin/bash
# STAGE 5, queued behind _html_diff_stage.sh (which is itself queued behind
# _finish_sequence.sh: pass A -> pass B -> audits). This drive therefore still
# runs at most ONE >1 GB job of its own at a time (coordinator directive 20:07).
#
# WHAT IT IS. The §16b pass on the POST-REPAIR corpus. Passes A and B measure
# populations that predate every §46 repair — every html dump in them is
# crash-truncated and neither contains a single run of the W10/W11 arms or of
# the 295 seed dimensions the three bulk rounds moved (§46.11). This is the
# pass whose verdict is about the endpoint as it now stands.
#
# It APPENDS ITS OWN PRINTED VERDICT LINES to _COMPLETION_20260910.md as §51.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
R="$B/_COMPLETION_20260910.md"
WAIT_PID="${1:-0}"
say(){ printf '%s\n' "$*" >> "$R"; }
[ "$WAIT_PID" != "0" ] && while kill -0 "$WAIT_PID" 2>/dev/null; do sleep 60; done

# Never start beside another >1 GB job of this drive's: wait for the slice to
# be free of a coverage_report.py of THIS endpoint.
while pgrep -f "posts_show/coverage_report.py" >/dev/null 2>&1; do sleep 60; done

say ""
say "## §51. THE POST-REPAIR PASS — §16b on the p5 corpus"
say ""
say '```'
{
  echo "launched $(date -Is)"
  echo "population _snapshot_pruned_p5.txt = $(wc -l < "$B/_snapshot_pruned_p5.txt") profiles of $(wc -l < "$B/_snapshot_20260910_p5.txt") dumps"
  echo "free -m at launch: $(free -m | awk 'NR==2{print "avail="$7"MB"}')"
} >> "$R"

systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=6G --unit=pxcovP5.scope \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" SUMMARY_OUT="$B/_cov_p5_pins.json" \
      SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=16 \
      python3 -u "$B/coverage_report.py" > "$B/_covP5_20260910.log" 2>&1
rc=$?
echo "pass P5 exit=$rc  finished $(date -Is)" >> "$R"
grep -E '^\[assumptions\]|^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|peak RSS|wrote|dump_errors)' \
     "$B/_covP5_20260910.log" >> "$R"
grep 'TREE-MISSING' "$B/_covP5_20260910.log" >> "$R"
grep 'FORECLOSURE-GATE' "$B/_covP5_20260910.log" | head -8 >> "$R"
say '```'
say ""
say "\`MAX_MISSING_PER_CLIQUE=16\` (not the default 4) DELIBERATELY: a pass on"
say "this endpoint costs hours of solver, so one pass must name as many demand"
say "targets as possible for the rounds that follow — the brief's \"name many"
say "targets per pass\". \`SKIP_COMPLETION=1\`, so \`OVERALL_COMPLETE\` is forced"
say "False by design; this pass measures the COVERAGE layer only."
say ""
say "PREDICTION, recorded before it ran (\`_tree_census_p5final.log\`, computed"
say "off the same pruned list through the engine's own load path): **TREE_MISSING"
say "= 0**. 137 tracked expressions, 13 one-sided, 8 of them the ARGUMENT P pins"
say "and the other 5 the \`photos ... status_message_guid != <itself>\`"
say "SELF-COMPARES, whose True side is unsatisfiable — and pass A proved"
say "empirically that Z3 excludes exactly those (its TREE_MISSING=11 contained"
say "none of them). If this pass reports any other number, the census and the"
say "engine disagree and THAT is the finding."
