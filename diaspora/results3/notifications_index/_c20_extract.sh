#!/bin/bash
# =============================================================================
# C20 EXTRACTION + SUBSUMPTION (RUNBOOK Phase 6) — run ONLY after the engine
# section prints OVERALL_COMPLETE=True.
#   usage: bash _c20_extract.sh <1|2>     1 = extract (syntactic subsumption
#                                             only), 2 = full blockaid solver
# Body from `_c11_extract.sh`; the changes are (a) the DUMP_LIST is this
# round's snapshot, (b) the shipped `queries_from_runs/notifications_index.sql`
# is BACKED UP with a dated name before the extractor may overwrite it, and
# (c) stage 2 runs the solver stage with SUBSUME_CACHE set.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
export QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json
STAGE="${1:?usage: _c20_extract.sh <1|2>}"
LIST="${DUMP_LIST:-$B/_snapshot_c20_R1.txt}"
CAP="${EXTRACT_CAP:-4G}"
L="$B/_c20_extract.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
. "$B/_wait_mem.sh"

# (b) the shipped policy is never overwritten without a dated backup
if [ ! -f "$Q/notifications_index.sql.bak_pre_c20_20260913" ] && [ -f "$Q/notifications_index.sql" ]; then
  cp -p "$Q/notifications_index.sql" "$Q/notifications_index.sql.bak_pre_c20_20260913"
  say "backed up shipped policy -> notifications_index.sql.bak_pre_c20_20260913 ($(wc -l < "$Q/notifications_index.sql") lines)"
fi

while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "WAIT free<4G"; sleep 30; done
wait_mem 4096 "_c20_extract-$STAGE" | tee -a "$L"
if [ "$STAGE" = 1 ]; then SK=1; TAG=syntactic; else SK=0; TAG=solver; fi
say "C20 EXTRACT stage $STAGE ($TAG)  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP"
systemd-run --user --scope --slice=concolic-cov.slice -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c20_extract_${STAGE}.time" \
  env DUMP_LIST="$LIST" SKIP_SUBSUME="$SK" \
      SUBSUME_CACHE="$B/_c20_subsume_cache.json" \
      QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
  /home/dev/project/venvs/queries_from_runs/bin/python -u \
    "$Q/_extract_notifications_index_streaming.py" > "$B/_c20_extract_${STAGE}.log" 2>&1
rc=$?
say "C20 EXTRACT stage $STAGE exit=$rc"
grep -E 'RED|views|distinct|subsum|unparseable|wrote|SKIP_SUBSUME' "$B/_c20_extract_${STAGE}.log" | tail -25 | tee -a "$L"
grep -E 'Maximum resident|Elapsed' "$B/_c20_extract_${STAGE}.time" | tee -a "$L"
if grep -qE 'wrote|views' "$B/_c20_extract_${STAGE}.log"; then
  say "C20-EXTRACT-${STAGE}-DONE"
else
  say "C20-EXTRACT-${STAGE}: *** NO OUTPUT LINE — TREAT AS KILLED, NOT DONE ***"; exit 40
fi
