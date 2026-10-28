#!/bin/bash
# P33 — measurement launcher (read-only; writes only _p33_*).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 2
/usr/bin/time -v -o "$B/_p33_criteria.time" \
  env DUMP_LIST="$B/_snapshot_pruned_P30C.txt" \
      MAX_CLIQUES=16384 CUBE_CAP=20000 LEAF_MAX=300000 \
      CRITERIA="${CRITERIA:-A_today,C3,C2,C2C3,SC2C3,SC3,SC2,S}" \
      JSON_OUT="$B/_p33_criteria.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p33_criteria.py"
echo "P33-RUN-EXIT=$?"
