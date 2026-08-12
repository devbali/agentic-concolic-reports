#!/usr/bin/env bash
# diaspora_rerun_all.sh — re-run every non-fully-complete diaspora batch with the
# Core::ClassMethods find mocks, replacing dumps. Runs batch runners sequentially.
# Each run_concolic.rb re-runs its full batch (its entrypoints).
set -u
PROJ=/home/dev/project
RESULTS=$PROJ/reports/diaspora/results
LOG=$PROJ/reports/diaspora/rerun_driver.log
: > "$LOG"

run_batch () {
  local batch="$1"; shift
  echo "===== BATCH $batch START $(date -u +%FT%TZ) =====" | tee -a "$LOG"
  for r in "$@"; do
    local f="$RESULTS/$batch/$r"
    if [ ! -f "$f" ]; then echo "  (no $r)" | tee -a "$LOG"; continue; fi
    echo "  -- runner: $r" | tee -a "$LOG"
    timeout 900 "$PROJ/scripts/diaspora-concolic" "$f" > "$RESULTS/$batch/${r%.rb}.rerun.log" 2>&1
    local rc=$?
    echo "    [$r rc=$rc] $(tail -1 "$RESULTS/$batch/${r%.rb}.rerun.log")" | tee -a "$LOG"
  done
  echo "===== BATCH $batch DONE $(date -u +%FT%TZ) =====" | tee -a "$LOG"
}

# Order: most find-affected first
run_batch comments       run_concolic.rb
run_batch likes          run_concolic.rb
run_batch services_admin run_concolic.rb
run_batch photos         run_concolic.rb
run_batch people         run_concolic.rb
run_batch posts          run_concolic.rb run_phase4.rb run_phase5.rb
run_batch contacts_aspects_blocks run_concolic.rb run_phase2.rb run_phase3.rb
run_batch conversations  run_concolic.rb run_phase2.rb run_phase3.rb
run_batch notifications_tags run_concolic.rb run_concolic_seeds.rb
run_batch streams        run_concolic.rb run_concolic_seeds.rb
run_batch users_sessions run_concolic.rb
run_batch oidc_federation_nodeinfo run_concolic.rb
run_batch search_links_reports_profiles run_concolic.rb

echo "ALL BATCHES COMPLETE $(date -u +%FT%TZ)" | tee -a "$LOG"
touch "$RESULTS/ALL_RERUN_DONE"
