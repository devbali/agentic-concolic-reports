#!/bin/bash
# Strictly sequential measurement queue for phase 3. Each stage waits for the
# previous to EXIT, so this drive still holds at most ONE >1 GB job of its own
# (pass B, which belongs to the earlier detached sequence, is the other).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
WAIT_PID="${1:-0}"
[ "$WAIT_PID" != "0" ] && while kill -0 "$WAIT_PID" 2>/dev/null; do sleep 20; done

# ---- stage 1: CONSISTENCY, checker vs enumerator, on PASS A's own snapshot --
# §51 (the p5 pass) is queued behind pass B + audits + the html stage and will
# not land for hours. Pass A is a landed §16b pass with its own summary
# (`_cov_pruned_baseline.json`) and its own snapshot, so the same comparison is
# available NOW, exactly, on one population.
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=5G --unit=pxconsA.scope \
  env DUMP_LIST="$B/_snapshot_pruned_20260910.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= SUMMARY="$B/_cov_pruned_baseline.json" \
      OUT="$B/_consistency_passA.json" \
  timeout 5400 python3 -u "$B/_consistency_check.py" > "$B/_consistency_passA.log" 2>&1
echo "EXIT=$? $(date -Is)" >> "$B/_consistency_passA.log"

# ---- stage 2: the p2 census — the BULK rate in ASSIGNMENT currency ---------
# p2 is the corpus the three bulk v3 rounds started from (14 806 profiles,
# 99 448 dumps). p5 is p2 + 30 000 bulk runs. covered(p5) - covered(p2) over
# 30 000 runs is the MEASURED closed/run of the bulk method, in the same
# currency the demand rounds will be judged in.
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=5G --unit=pxenumP2.scope \
  env DUMP_LIST="$B/_snapshot_pruned_p2.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= \
  timeout 3600 python3 -u "$B/_exact_enum_emit.py" --json-out "$B/_enum_p2.json" \
  > "$B/_enum_p2.log" 2>&1
echo "EXIT=$? $(date -Is)" >> "$B/_enum_p2.log"
