#!/bin/bash
# Runs the what-if census on p5 once the round's own census has exited, and
# only if there is room: never start a >1 GB job of this drive's beside another.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
W="${1:-0}"
[ "$W" != "0" ] && while kill -0 "$W" 2>/dev/null; do sleep 15; done
# wait for room (>= 5000 MB available) and for no other census of this drive
while :; do
  avail=$(free -m | awk 'NR==2{print $7}')
  busy=$(pgrep -f "posts_show/_exact_enum_emit.py" | wc -l)
  [ "$avail" -ge 5000 ] && [ "$busy" -eq 0 ] && break
  sleep 30
done
echo "starting what-if at $(date -Is), avail=$(free -m | awk 'NR==2{print $7}')MB" \
  > "$B/_whatif_indep.log"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=5G --unit=pxwhatif.scope \
  env DUMP_LIST="$B/_snapshot_pruned_p5.txt" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  timeout 3600 python3 -u "$B/_whatif_indep.py" >> "$B/_whatif_indep.log" 2>&1
echo "EXIT=$? $(date -Is)" >> "$B/_whatif_indep.log"
