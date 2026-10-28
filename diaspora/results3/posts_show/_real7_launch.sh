#!/usr/bin/env bash
# REAL7 launch wrapper for posts_show's coverage_report.py.
#
# Same corpus/config as REAL6 (§123.21), PLUS:
#   - completion_config.json JSON bug fixed (unescaped quotes around
#     $DUMP_LIST in note_check_cmd) -- see _p44_status.md §123.22.
#   - COVERAGE_CHECKPOINT added (RUNBOOK rule: "anything that can run longer
#     than ~10 minutes is launched with its checkpoint on"), which REAL6
#     omitted -- that omission is why REAL6's ~7290s of completed Z3
#     coverage work was lost when it crashed in attach_to_summary before
#     coverage_summary.json was written. A REAL8, if ever needed, can now
#     resume step 6 from _real7_coverage.ckpt.jsonl instead of redoing it.
set -euo pipefail
cd /home/dev/project

B=/home/dev/project/reports/diaspora/results3/posts_show

exec env \
  DUMP_LIST="$B/_snapshot_pruned_P44FRESH2.txt" \
  ACHK_CHECKPOINT="$B/_real4_probes.ckpt.jsonl" \
  ACHK_INDEX_CHECKPOINT="$B/_real4_index.ckpt.jsonl" \
  COVERAGE_CHECKPOINT="$B/_real7_coverage.ckpt.jsonl" \
  CONCOLIC_SLOTS=14 \
  CONCOLIC_PROBE_WORKERS=14 \
  JAVA_TOOL_OPTIONS= \
  PYTHONPATH=/home/dev/project/src \
  /usr/bin/time -v -o "$B/_coveragecheck_REAL7.time" \
  python3 -u "$B/coverage_report.py"
