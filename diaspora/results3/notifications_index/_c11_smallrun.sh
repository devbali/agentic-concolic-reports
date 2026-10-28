#!/bin/bash
# A SMALL analysis job (measured peak well under 400 MB) still runs CAGED and
# choom'd, but in its OWN slice: concolic-cov.slice is over MemoryHigh while
# another batch's 3 GB job runs there, and anything added to it is throttled in
# reclaim (`mem_cgroup_handle_over_high`) rather than run. MemoryMax=400M is the
# claim being enforced: if the job is not small, it dies instead of competing.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
LABEL="$1"; CAP="$2"; shift 2
fg=$(free -m | awk '/^Mem/{print $7}')
echo "[$(date -Is)] $LABEL LAUNCH(small-slice): free=${fg}MB cap=${CAP}M"
systemd-run --user --scope --slice=concolic-small.slice -p MemoryMax=${CAP}M -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= "$@" \
  > "$B/_c11_${LABEL}.out" 2>&1
echo "[$(date -Is)] $LABEL EXIT rc=$?" | tee -a "$B/_c11_${LABEL}.out"
