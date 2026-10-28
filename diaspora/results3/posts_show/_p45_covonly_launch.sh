#!/usr/bin/env bash
# P45: coverage-ONLY measurement pass (no assumption gate, no audits).
#
# Question it answers: the REAL10 summary carries
#   coverage_numbers_stale = "STALE: confined pair(s) FAILED the gate;
#   missing/demand above were computed with them licensed"
# i.e. REAL10's MISSING/DEMAND_SETS were computed while the 460 gate-FAILED
# and 464 NOT-TESTABLE confined pairs were still licensed, and while the
# fed-back withdrawal file (_confinement_withdrawn.json, 2026-09-15, 564
# pairs) had ZERO overlap with the 924 pairs THIS pass's gate refused.
#
# This pass re-runs coverage alone with the union of both sets (1488 pairs)
# withdrawn, everything else identical to _real8_launch.sh, so the two
# coverage censuses are directly comparable:
#   control  (REAL10, 564 stale pairs fed): 1008 demand sets,
#            234 with no gap, 774 with a gap, 531 truncated at cap 4
#   treatment(this pass, 1488 pairs fed)  : ?
#
# Checkpoints: writes a FRESH file (_p45_coverage.ckpt.jsonl). _real7 is
# preserved untouched -- its demands key no longer matches anyway.
set -euo pipefail
cd /home/dev/project

B=/home/dev/project/reports/diaspora/results3/posts_show

exec env \
  DUMP_LIST="$B/_snapshot_pruned_P44FRESH2.txt" \
  WITHDRAWN_PAIRS_FILE="$B/_confinement_withdrawn_P45.json" \
  COVERAGE_CHECKPOINT="$B/_p45_coverage.ckpt.jsonl" \
  SUMMARY_OUT="$B/_cov_P45_withdraw1488.json" \
  SKIP_COMPLETION=1 \
  MAX_MISSING_PER_CLIQUE=4 \
  HEARTBEAT_SECS=300 \
  JAVA_TOOL_OPTIONS= \
  PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/coverage_report.py"
