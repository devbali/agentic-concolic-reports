#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
F="$1"; TK="$2"; V="$3"; TAG="$4"
N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
SFX="_${TAG}${TK}$(echo "$V" | cut -c1-2)$(echo "$V" | cut -d_ -f2 | cut -c1-2)"
/home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
  EXTRA_SEEDS_JSON="$F" LABEL_SUFFIX="$SFX" \
  MAX_RUNS=100000 TIME_BUDGET=1800 \
  /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" \
  > "$B/_treelog_${TAG}_${TK}_${V}.log" 2>&1
rc=$?
got=$(find "$B" -maxdepth 1 -name "dump_*${SFX}.json" | wc -l)
echo "[$(date -Is)] $TK $V seeds=$N rc=$rc dumps=$got suffix=$SFX" >> "$B/_tree_drive_${TAG}.log"
