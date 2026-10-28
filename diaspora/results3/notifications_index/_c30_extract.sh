#!/bin/bash
# =============================================================================
# C30 EXTRACTION + SUBSUMPTION (RUNBOOK Phase 6) — run ONLY after the engine
# section prints OVERALL_COMPLETE=True with `blocking: []`.
#   usage: DUMP_LIST=<abs snapshot> bash _c30_extract.sh <1|2>
#          1 = extract (syntactic subsumption only)
#          2 = full blockaid solver stage (SUBSUME_CACHE set)
#
# COPY of `_c20_extract.sh` (§29.9's rule: copy, never edit a script an earlier
# round is judged by). THREE differences, each stated:
#
#  1. `--no-block --unit=` with `StandardOutput=file:`, NOT `--scope`. C24's
#     defect: a `--scope` client (and a BLOCKING `--unit` client) is killed
#     with the session that launched it — two hour-long jobs were lost to it
#     on 2026-09-13. The wrapper LAUNCHES and returns; the verdict is judged
#     by `bash _c30_extract.sh --verdict <1|2>` or by reading the log.
#  2. A FRESH DATED BACKUP of the shipped policy, `…sql.bak_pre_c30_20260915`.
#     `_c20_extract.sh`'s guard only ever wrote `…bak_pre_c20_20260913`, so a
#     second extraction would have overwritten the shipped file with no backup
#     of the version it replaced.
#  3. DUMP_LIST has no in-script default — the snapshot is named on the
#     launch line, because a wrong corpus here is a wrong shipped policy.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
export QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json
L="$B/_c30_extract.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
cd "$B" || exit 2

if [ "$1" = "--verdict" ]; then
  STAGE="${2:?usage: _c30_extract.sh --verdict <1|2>}"
  LG="$B/_c30_extract_${STAGE}.log"
  if grep -qE 'wrote|views' "$LG" 2>/dev/null; then
    say "VERDICT C30-EXTRACT-$STAGE: OK (line present)"
    grep -E 'RED|views|distinct|subsum|unparseable|wrote|SKIP_SUBSUME' "$LG" | tail -30 | tee -a "$L"
    grep -E 'Maximum resident|Elapsed' "$B/_c30_extract_${STAGE}.time" 2>/dev/null | tee -a "$L"
    say "C30-EXTRACT-${STAGE}-DONE"
    exit 0
  fi
  say "VERDICT C30-EXTRACT-$STAGE: *** NO OUTPUT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LG" 2>/dev/null | sed 's/^/    /' | tee -a "$L"
  exit 40
fi

STAGE="${1:?usage: DUMP_LIST=<abs snapshot> _c30_extract.sh <1|2>}"
LIST="${DUMP_LIST:?DUMP_LIST is REQUIRED — refusing to guess a corpus}"
[ -s "$LIST" ] || { say "*** DUMP_LIST=$LIST missing/empty ***"; exit 2; }
CAP="${EXTRACT_CAP:-8G}"; CAPMB="${EXTRACT_CAPMB:-8192}"
. "$B/_wait_mem.sh"

# (2) the shipped policy is never overwritten without a dated backup
STAMPBAK="$Q/notifications_index.sql.bak_pre_c30_$(date +%Y%m%d)"
if [ -f "$Q/notifications_index.sql" ] && [ ! -f "$STAMPBAK" ]; then
  cp -p "$Q/notifications_index.sql" "$STAMPBAK"
  say "backed up shipped policy -> $(basename "$STAMPBAK") ($(wc -l < "$Q/notifications_index.sql") lines, md5 $(md5sum "$Q/notifications_index.sql" | cut -d' ' -f1))"
else
  say "backup $(basename "$STAMPBAK") already present — not overwritten"
fi

while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "WAIT free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c30_extract-$STAGE" | tee -a "$L"
if [ "$STAGE" = 1 ]; then SK=1; TAG=syntactic; else SK=0; TAG=solver; fi
say "C30 EXTRACT stage $STAGE ($TAG)  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP"
systemd-run --user --no-block --unit="notif-c30-extract-${STAGE}" \
  --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c30_extract_${STAGE}.log" \
  -p StandardError="append:$B/_c30_extract_${STAGE}.log" \
  --setenv=DUMP_LIST="$LIST" --setenv=SKIP_SUBSUME="$SK" \
  --setenv=SUBSUME_CACHE="$B/_c20_subsume_cache.json" \
  --setenv=QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json \
  --setenv=PYTHONPATH=/home/dev/project/src --setenv=JAVA_TOOL_OPTIONS= \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c30_extract_${STAGE}.time" \
  /home/dev/project/venvs/queries_from_runs/bin/python -u \
    "$Q/_extract_notifications_index_streaming.py"
say "C30 EXTRACT stage $STAGE LAUNCHED unit=notif-c30-extract-${STAGE} log=$B/_c30_extract_${STAGE}.log"
