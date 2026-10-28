#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
# wait for the shipped 83-class run to release the heavy lock
while pgrep -f 'assumption_checker.py .*_tier2_declared.json' >/dev/null 2>&1; do sleep 20; done
bash "$B/_tier2_negcontrol.sh"
