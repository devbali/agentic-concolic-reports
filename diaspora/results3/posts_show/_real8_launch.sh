#!/usr/bin/env bash
# REAL8 launch wrapper for posts_show's coverage_report.py.
#
# Same corpus/config as REAL7 (checkpoints preserved via manual header
# hash-patch after src/end_to_end_completion_checker/assumption/
# assumption_checker.py commit 8ceccfb removed run_probe's fixed 900s
# inner timeout -- see that commit message and the coordinator session log,
# 2026-09-22), PLUS:
#   - ACHK_CONF_PROFILES=500 (was unset/0 = unlimited): bounds the
#     exhaustive confinement-assumption profile enumeration that blocked
#     REAL7's assumption gate for 12h+ without testing a single assumption
#     (one near-universal decision, Length(SYM_PARAM_id) < 16, had 280,000+
#     distinct outcome-profiles in this 720k-dump corpus). 500 is a
#     judgment call: the profile ranking already prefers the richest
#     (most-shapes-carried) representatives first, so this keeps the
#     strongest evidence; anything beyond the cap degrades that pair to
#     NOT-TESTABLE rather than an unsound PASS -- never wrong-in-silence.
set -euo pipefail
cd /home/dev/project

B=/home/dev/project/reports/diaspora/results3/posts_show

exec env \
  DUMP_LIST="$B/_snapshot_pruned_P44FRESH2.txt" \
  ACHK_CHECKPOINT="$B/_real4_probes.ckpt.jsonl" \
  ACHK_INDEX_CHECKPOINT="$B/_real4_index.ckpt.jsonl" \
  COVERAGE_CHECKPOINT="$B/_real7_coverage.ckpt.jsonl" \
  ACHK_CONF_PROFILES=500 \
  CONCOLIC_SLOTS=6 \
  CONCOLIC_PROBE_WORKERS=6 \
  JAVA_TOOL_OPTIONS= \
  PYTHONPATH=/home/dev/project/src \
  /usr/bin/time -v -o "$B/_coveragecheck_REAL8.time" \
  python3 -u "$B/coverage_report.py"
