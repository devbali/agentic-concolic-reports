#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
L="$B/_p27_probe.log"; : > "$L"
export DUMP_LIST="$B/_snapshot_pruned_P26D2.txt"
export OUT="$B/_p27_state.jsonl"
cage p27probe 6G python3 -u "$B/_p27_probe.py" >>"$L" 2>&1
echo "exit=$?" >>"$L"
caged_verdict p27probe "$L" 'P27-PROBE-DONE' >>"$L" 2>&1
