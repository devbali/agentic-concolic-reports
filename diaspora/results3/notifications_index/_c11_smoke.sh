#!/bin/bash
# SMOKE: the withdrawal wiring on a 300-dump slice (no claim about coverage —
# it proves the code path: W-G count printed, withdrawn_pairs/prior_footprints
# accepted by CoverageChecker, summary written).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
S=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad
. "$B/_wait_mem.sh"
cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value); head=$(( (6442450944 - ${cur:-0}) / 1048576 ))
echo "[$(date -Is)] smoke LAUNCH(small): cage_headroom=${head}MB cap=1000MB free=$(free -g|awk '/^Mem/{print $7}')G"
systemd-run --user --scope --slice=concolic-cov.slice -p MemoryMax=1000M -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- env DUMP_LIST="$S/smoke300.txt" PYTHONPATH=/home/dev/project/src \
  SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE=2 MISSING_CAP=50 \
  SUMMARY_OUT="$S/smoke_summary.json" NO_GATE_WITHDRAW="${NO_GATE_WITHDRAW:-}" \
  JAVA_TOOL_OPTIONS= python3 -u "$B/coverage_report.py" > "$B/_c11_smoke${TAG:-}.log" 2>&1
echo "[$(date -Is)] smoke EXIT rc=$?"
grep -E '^\[assumptions\]|^\[confinement\]|^COMPLETE=|^OVERALL|Confinement|WITHDRAWN' "$B/_c11_smoke${TAG:-}.log" | head -20
