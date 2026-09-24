#!/bin/bash
# Extraction step, ready to run once coverage_report.py (vbcov2) is done.
# Wrapped in systemd-run per the overnight memory-watchdog notice.
set -uo pipefail
V=/home/dev/project/reports/diaspora/results3/_experiment/variant_b
cd /home/dev/project
flock /tmp/concolic-slot.lock systemd-run --user -p MemoryMax=2500M -p MemorySwapMax=0 --wait --unit=vbextract_$$ bash -c '
cd /home/dev/project
unset JAVA_TOOL_OPTIONS
PYTHONPATH=src venvs/queries_from_runs/bin/python -m queries_from_runs.dump \
  --app-config /home/dev/project/reports/diaspora/queries_config/app.json \
  --results reports/diaspora/results3/_experiment \
  --out reports/diaspora/results3/_experiment/variant_b/queries_out \
  --endpoint variant_b \
  --summary-json reports/diaspora/results3/_experiment/variant_b/queries_out/_summary.json \
  --verbose
' > $V/_extraction.log 2>&1
echo "EXTRACTION EXIT: $?"
mkdir -p $V/diff_ours
cp $V/queries_out/variant_b.sql $V/diff_ours/notifications_index.sql
wc -l $V/diff_ours/notifications_index.sql
cat $V/queries_out/_summary.json
