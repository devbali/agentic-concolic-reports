#!/bin/bash
# C17 single-run verification: control vs C17-fixed seed, one JRuby, caged 2G.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd /home/dev/project || exit 1
. "$B/_wait_mem.sh"
wait_mem 2048 c17-verify
systemd-run --user --slice=concolic-cov.slice --scope \
  -p MemoryMax=2G -p MemorySwapMax=0 --quiet choom -n 1000 -- \
  /home/dev/project/reports/diaspora/tools/slot env VARIANTS=html_typed SEEDS_ONLY=1 \
  EXTRA_SEEDS_JSON="$B/_c17_verify_seeds.json" \
  LABEL_SUFFIX="_C17V" MAX_RUNS=10 TIME_BUDGET=1200 \
  /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$B/_c17_verify_drive.log" 2>&1
echo "rc=$? C17-VERIFY-DRIVE-END"
