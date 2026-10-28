#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
W="${1:-0}"
[ "$W" != "0" ] && while kill -0 "$W" 2>/dev/null; do sleep 20; done
bash "$B/_tier2_gate3.sh"
