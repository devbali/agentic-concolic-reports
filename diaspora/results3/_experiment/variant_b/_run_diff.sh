#!/bin/bash
# Diff step, ready to run once extraction (diff_ours/notifications_index.sql)
# exists. Wrapped in systemd-run per the overnight memory-watchdog notice.
# This is the slow step (blockaid/z3, SUBSUME_TIMEOUT_MS=120000 per query).
set -uo pipefail
V=/home/dev/project/reports/diaspora/results3/_experiment/variant_b
cd /home/dev/project
flock /tmp/concolic-slot.lock systemd-run --user -p MemoryMax=3200M -p MemorySwapMax=0 --wait --unit=vbdiff4_$$ bash -c '
cd /home/dev/project
SUBSUME_TIMEOUT_MS=15000 SUBSUME_SOLVER_THREADS=1 PYTHONPATH=src venvs/queries_from_runs/bin/python -m queries_from_runs.diff \
  --reference ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint \
  --ours reports/diaspora/results3/_experiment/variant_b/diff_ours \
  --out reports/diaspora/results3/_experiment/variant_b/diff \
  --timeout-ms 15000 \
  --parallel 1 \
  --incremental \
  --endpoint notifications_index \
  --verbose
' > $V/_diff4.log 2>&1
echo "DIFF EXIT: $?"
cat $V/diff/_summary.json 2>/dev/null
