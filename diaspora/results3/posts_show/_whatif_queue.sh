#!/bin/bash
# Queued so it never runs beside the gate or the negative control.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
while pgrep -f 'assumption_checker.py' >/dev/null 2>&1; do sleep 20; done
while [ "$(free -m | awk 'NR==2{print $7}')" -lt 5000 ]; do sleep 30; done
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=5G --unit=pxwfmerge.scope \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  timeout 3600 python3 -u "$B/_whatif_wf_merge.py" > "$B/_whatif_wf_merge.log" 2>&1
echo "EXIT=$? $(date -Is)" >> "$B/_whatif_wf_merge.log"
