#!/bin/bash
# EXTRACTION (RUNBOOK Phase 6) — E1 fold + E11 RED check + DUMP_LIST, with the
# subsumption stage as the harness supplies it (syntactic, then blockaid).
# QFR_APP_CONFIG hand-off is in the extractor itself; exported here too.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
export QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json
CAP="${EXTRACT_CAP:-2500M}"
. "$B/_wait_mem.sh"; wait_mem "${CAP%M}" "_c11_extract"
echo "[$(date -Is)] extraction start cap=$CAP"
systemd-run --user --scope --slice=concolic-cov.slice -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c11_extract.time" \
  env DUMP_LIST="$B/_snapshot_pruned_20260911_143539.txt" \
      SKIP_SUBSUME="${SKIP_SUBSUME:-1}" \
      QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  /home/dev/project/venvs/queries_from_runs/bin/python -u \
    "$Q/_extract_notifications_index_streaming.py" > "$B/_c11_extract.log" 2>&1
rc=$?
[ "$rc" = "0" ] && touch "$B/_c11_extract.ok"
echo "[$(date -Is)] extraction EXIT rc=$rc"
grep -E 'RED|views|distinct|subsum|unparseable|wrote' "$B/_c11_extract.log" | tail -20
grep -E 'Maximum resident' "$B/_c11_extract.time"
