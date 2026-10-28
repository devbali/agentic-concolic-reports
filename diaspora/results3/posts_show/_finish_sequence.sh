#!/bin/bash
# STRICTLY SEQUENTIAL closing sequence for posts_show (2026-09-10 drive).
# Never more than ONE >1 GB job of this drive's own at a time (coordinator
# directive, 20:07). Each stage waits for the previous to EXIT, and each
# stage APPENDS ITS OWN PRINTED VERDICT LINES to _COMPLETION_20260910.md so
# the record completes whether or not an agent is watching.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
R="$B/_COMPLETION_20260910.md"
A_PID="${1:-0}"
say(){ printf '%s\n' "$*" >> "$R"; }

# ---- stage 1: wait for the baseline pass that is already running -----------
if [ "$A_PID" != "0" ]; then
  while kill -0 "$A_PID" 2>/dev/null; do sleep 60; done
fi
say ""
say "## §38. PASS A — the BASELINE §16b verdict, verbatim"
say ""
say '```'
grep -E '^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|peak RSS|wrote|dump_errors)' \
     "$B/_covA_pruned_20260910.log" >> "$R"
grep 'TREE-MISSING' "$B/_covA_pruned_20260910.log" >> "$R"
grep 'FORECLOSURE-GATE' "$B/_covA_pruned_20260910.log" | head -8 >> "$R"
say '```'
say ""
say "Population: \`_snapshot_pruned_20260910.txt\`, 14 742 distinct outcome"
say "profiles of the preflight's 96 357 dumps — an EXACT prune, verified"
say "(§16). Pins were NOT installed when this pass started, so this is the"
say "pre-pin, pre-drive state: **this endpoint's first-ever §16b measurement**."
say "The preflight's attempt was OOM-killed inside the LOAD at 3 GB and printed"
say "nothing at all."

# ---- stage 2: the pinned pass, ALONE --------------------------------------
say ""
say "## §39. PASS B — the PINNED pass on the grown corpus"
say ""
say "Run ALONE, after pass A exited (coordinator directive §36)."
say ""
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=6G --unit=pxcovB2.scope \
  env DUMP_LIST="$B/_snapshot_pruned_p2.txt" SUMMARY_OUT="$B/_cov_p2_pins.json" SKIP_COMPLETION=1 \
  python3 -u "$B/coverage_report.py" > "$B/_covB2_p2_20260910.log" 2>&1
rc=$?
say '```'
echo "pass B exit=$rc" >> "$R"
grep -E '^\[assumptions\]|^(COMPLETE|GENUINE|dumps_loaded|DEMAND_SETS|peak RSS|wrote|dump_errors)' \
     "$B/_covB2_p2_20260910.log" >> "$R"
grep 'TREE-MISSING' "$B/_covB2_p2_20260910.log" >> "$R"
grep 'FORECLOSURE-GATE' "$B/_covB2_p2_20260910.log" | head -8 >> "$R"
say '```'
say ""
say "Population: \`_snapshot_pruned_p2.txt\`, 14 806 distinct outcome profiles of"
say "99 448 dumps (after TR0910a + TR0910w), with the seven ARGUMENT P pins."
say "\`SKIP_COMPLETION=1\`, so \`OVERALL_COMPLETE\` is forced False by design —"
say "this pass measures the COVERAGE layer only."

# ---- stage 3: the audit suite, ALONE --------------------------------------
say ""
say "## §40. The audit suite, re-run at 6 GB, alone"
say ""
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=6G --unit=pxaudits3.scope \
  bash "$B/_c7_audits.sh" > "$B/_c7_audits.out" 2>&1
say '```'
grep -n 'EXIT=' "$B/_c7_audits.log" >> "$R"
say '```'
say ""
say "_(appended automatically by \`_finish_sequence.sh\`; the full logs are"
say "\`_covA_pruned_20260910.log\`, \`_covB2_p2_20260910.log\` and \`_c7_audits.log\`.)_"
