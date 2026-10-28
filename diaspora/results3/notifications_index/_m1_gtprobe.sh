#!/bin/bash
# M-SNAP GROUND-TRUTH DIFFERENTIAL (2026-09-12) — the FALSIFIER the declaration
# names, run directly: seed the actors-list length 0..5 at the RUNTIME (ordinal)
# key on one rich snapshot, replay, and read back the value the mock MINTED.
# The declaration is refuted iff some seed makes the mock return 2 or 3.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
. "$B/_wait_mem.sh"
wait_mem 2048 "_m1/gtprobe" | tee -a "$B/_m1.log"
cd /home/dev/project || exit 2
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax=3G -p MemorySwapMax=0 --quiet choom -n 1000 -- \
  env CONCOLIC_SLOTS=3 SEEDS_ONLY=1 VARIANTS=html_plain JAVA_TOOL_OPTIONS= \
      EXTRA_SEEDS_JSON="$B/_msnap_gt_seeds.json" LABEL_SUFFIX=_msnapgt \
      "/home/dev/project/reports/diaspora/tools/slot" \
      "/home/dev/project/scripts/diaspora-concolic" "$B/run_dse.rb" > "$B/_m1_gtprobe.log" 2>&1
echo "[$(date -Is)] M1-GTPROBE exit=$? dumps=$(ls -U "$B" | grep -c '_msnapgt')" | tee -a "$B/_m1.log"
