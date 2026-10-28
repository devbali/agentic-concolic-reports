#!/bin/bash
# =============================================================================
# C27 EXTRACTION + SUBSUMPTION (RUNBOOK Phase 6) — run ONLY after the engine
# section prints OVERALL_COMPLETE=True with blocking: [].
#   usage: bash _c27_extract.sh <1|2>     1 = extract (syntactic subsumption
#                                             only), 2 = full blockaid solver
# Body from `_c20_extract.sh`; three changes:
#   (a) DUMP_LIST is C27's corpus snapshot (_snapshot_c24_R2.txt, 135 153 runs);
#   (b) the shipped policy gets a DATED backup before the extractor may write;
#   (c) --no-block --unit= + StandardOutput=file:, not --scope (a --scope
#       client dies with the launching session and takes the job with it).
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
export QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json
STAGE="${1:?usage: _c27_extract.sh <1|2>}"
LIST="${DUMP_LIST:-$B/_snapshot_c24_R2.txt}"
CAP="${EXTRACT_CAP:-4G}"; CAPMB="${EXTRACT_CAPMB:-4096}"
L="$B/_c27_extract.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
. "$B/_wait_mem.sh"

# (b) the shipped policy is never overwritten without a DATED backup
if [ ! -f "$Q/notifications_index.sql.bak_pre_c27_20260914" ] && [ -f "$Q/notifications_index.sql" ]; then
  cp -p "$Q/notifications_index.sql" "$Q/notifications_index.sql.bak_pre_c27_20260914"
  say "backed up shipped policy -> notifications_index.sql.bak_pre_c27_20260914 ($(wc -l < "$Q/notifications_index.sql") lines)"
fi

while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "WAIT free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c27_extract-$STAGE" | tee -a "$L"
if [ "$STAGE" = 1 ]; then SK=1; TAG=syntactic; else SK=0; TAG=solver; fi
say "C27 EXTRACT stage $STAGE ($TAG)  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP"
systemd-run --user --no-block --unit="notif-c27-extract-${STAGE}" \
  --slice=concolic-cov.slice -p MemoryMax="$CAP" -p MemorySwapMax=0 \
  -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c27_extract_${STAGE}.log" \
  -p StandardError="append:$B/_c27_extract_${STAGE}.log" \
  --setenv=DUMP_LIST="$LIST" --setenv=SKIP_SUBSUME="$SK" \
  --setenv=SUBSUME_CACHE="$B/_c27_subsume_cache.json" \
  --setenv=QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json \
  --setenv=PYTHONPATH=/home/dev/project/src --setenv=JAVA_TOOL_OPTIONS= \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c27_extract_${STAGE}.time" \
  /home/dev/project/venvs/queries_from_runs/bin/python -u \
    "$Q/_extract_notifications_index_streaming.py"
say "C27 EXTRACT stage $STAGE LAUNCHED unit=notif-c27-extract-${STAGE} log=$B/_c27_extract_${STAGE}.log"
