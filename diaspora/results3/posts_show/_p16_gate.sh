#!/bin/bash
# THE ASSUMPTION GATE, run on the NEW DECLARATION ONLY (§79). Same shape as
# _tier2_gate3.sh: the shipped driver, a `--declared` file holding just the
# classes under test, results checkpointed so a kill leaves evidence.
set +e; unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
LOG="$B/_p16_gate.log"
echo "=== P16 gate (render-ordinal identity, declared-only) start $(date -Is) ===" > "$LOG"
free -m | sed -n 2p >> "$LOG"
export CONCOLIC_SLOTS=1
export ACHK_CHECKPOINT="$B/_p16_achk_probes.jsonl"
export ACHK_RESULTS_JSONL="$B/_p16_achk_rows.jsonl"
cage p16gate.scope 4G \
  env CONCOLIC_SLOTS=1 JAVA_TOOL_OPTIONS= \
      ACHK_CHECKPOINT="$ACHK_CHECKPOINT" ACHK_RESULTS_JSONL="$ACHK_RESULTS_JSONL" \
      PYTHONPATH=/home/dev/project/src \
  python3 -u /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  "$B/assumption_manifest.json" --declared "$B/_p16_declared.json" \
  --json-out "$B/_p16_probe_results.json" >> "$LOG" 2>&1
rc=$?
echo "=== P16 gate DONE rc=$rc $(date -Is) ===" >> "$LOG"
