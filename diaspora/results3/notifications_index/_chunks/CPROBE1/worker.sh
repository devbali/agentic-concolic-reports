#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
V="$1"; C="$2"; TAG="$3"; CD="$B/_chunks/$TAG"
SFX="$( [ "${V##*_}" = typed ] && echo t || echo p )"
OUT="$CD/log_${V}_${C}.log"
[ -f "$CD/done_${V}_${C}" ] && exit 0
/home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
  EXTRA_SEEDS_JSON="$CD/c${C}.json" \
  LABEL_SUFFIX="_${TAG}${V:0:3}${SFX}${C}" \
  MAX_RUNS=100000 TIME_BUDGET=3600 \
  /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$OUT" 2>&1
rc=$?
n=$(grep -c 'new path' "$OUT")
crash=$(grep -c 'fatal error\|invalid pointer\|SIGSEGV' "$OUT")
echo "[$(date -Is)] $V c$C rc=$rc paths=$n crash=$crash" >> "$B/_chunk_drive_${TAG}.log"
touch "$CD/done_${V}_${C}"
# keep the directory small: only crashed chunks keep their log
[ "$crash" = "0" ] && rm -f "$OUT"
