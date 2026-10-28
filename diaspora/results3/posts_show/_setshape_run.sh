#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=5G --unit=pxshapeP5.scope \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  timeout 3600 python3 -u "$B/_setshape.py" > "$B/_setshape_p5.log" 2>&1
echo "EXIT=$? $(date -Is)" >> "$B/_setshape_p5.log"
