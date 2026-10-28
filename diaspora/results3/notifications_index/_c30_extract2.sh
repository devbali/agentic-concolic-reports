#!/bin/bash
# =============================================================================
# C30 EXTRACTION, STAGE 2 — the SOLVER subsumption stage, on the PARALLEL
# extractor.  Judged by its own `wrote|views` output line
# (`bash _c30_extract2.sh --verdict`).
#
#   usage: DUMP_LIST=<abs snapshot> bash _c30_extract2.sh
#
# WHY A SECOND SCRIPT AND NOT `_c30_extract.sh 2`. `_c30_extract.sh 2` re-runs
# the SERIAL driver, which measured 2 h 58 m over 138 912 dumps at 96 % of ONE
# core, and the solver stage needs the whole 708-query deduped list WITH its
# per-query flags, so it cannot be fed from stage 1's emitted `.sql` (that file
# holds only the 109 syntactic survivors and none of the flags).
# `_c30_extract_par.py` shards the scan at the DRIVER (multiprocessing Pool over
# chunks of dumps, merged IN ORDER so first-seen is byte-identically the serial
# answer). Nothing was added to `src/`.
#
#   GROUND-TRUTH DIFFERENTIAL, run before this script was used:
#     3 000-dump list, SKIP_SUBSUME=1, serial vs parallel
#       serial   2 m 55 s   106 queries (227 distinct, 121 subsumed)
#       parallel 0 m 56 s   106 queries (227 distinct, 121 subsumed)
#       `diff serial.sql par.sql` -> IDENTICAL
#
# SUBSUMPTION WIDTH. The harness ALREADY takes a width knob, so no driver-level
# sharding of the pairwise loop is needed and none is added:
#   SUBSUME_SOLVER_THREADS   concurrent z3 processes (default 4) -> 6 here
#   SUBSUME_TIMEOUT_MS       per-pair solver timeout (default 3000) -- LEFT AT
#                            THE DEFAULT, because changing it changes verdicts
#   SUBSUME_PREFILTER        left at 1
#
# NULL = TIMEOUT = KEPT, guaranteed by construction, not by convention.
# `subsume/java/SubsumeChecker.java:87-93`: "queries[i] is reported subsumed by
# queries[j] iff ... proven UNSAT by z3 within the per-pair timeout. Timeouts /
# sat / unknown are treated as 'not subsumed' -- only verified pairs are
# reported." A pair only ever ENTERS `subsumed` on a proof; everything else is
# absent from the result and the query therefore SURVIVES. Raising the thread
# count changes how many pairs are in flight, never how a pair is judged, so a
# widened run can only be slower or faster, never less conservative.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
export QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json
L="$B/_c30_extract.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
cd "$B" || exit 2

if [ "$1" = "--verdict" ]; then
  LG="$B/_c30_extract_2.log"
  if grep -qE 'queries \(|wrote' "$LG" 2>/dev/null; then
    say "VERDICT C30-EXTRACT-2: OK (line present)"
    grep -E 'RED|parallel|cache|subsume|distinct|queries \(' "$LG" | tail -20 | tee -a "$L"
    grep -E 'Maximum resident|Elapsed' "$B/_c30_extract_2.time" 2>/dev/null | tee -a "$L"
    say "C30-EXTRACT-2-DONE"; exit 0
  fi
  say "VERDICT C30-EXTRACT-2: *** NO OUTPUT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LG" 2>/dev/null | sed 's/^/    /' | tee -a "$L"; exit 40
fi

LIST="${DUMP_LIST:?DUMP_LIST is REQUIRED — refusing to guess a corpus}"
[ -s "$LIST" ] || { say "*** DUMP_LIST=$LIST missing/empty ***"; exit 2; }
CAP="${EXTRACT_CAP:-12G}"; CAPMB="${EXTRACT_CAPMB:-12288}"
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do say "WAIT free<4G"; sleep 30; done
wait_mem "$CAPMB" "_c30_extract-2" | tee -a "$L"
say "C30 EXTRACT stage 2 (solver)  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP  workers=${EXTRACT_WORKERS:-6}  solver_threads=${SUBSUME_SOLVER_THREADS:-6}"
systemd-run --user --no-block --unit="notif-c30-extract-2" --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet -p WorkingDirectory="$B" \
  -p StandardOutput="file:$B/_c30_extract_2.log" \
  -p StandardError="append:$B/_c30_extract_2.log" \
  --setenv=DUMP_LIST="$LIST" \
  --setenv=EXTRACT_WORKERS="${EXTRACT_WORKERS:-6}" \
  --setenv=EXTRACT_CHUNK="${EXTRACT_CHUNK:-200}" \
  --setenv=QUERIES_OUT="$B/_c30_deduped_queries.json" \
  --setenv=SUBSUME_CACHE="$B/_c20_subsume_cache.json" \
  --setenv=SUBSUME_SOLVER_THREADS="${SUBSUME_SOLVER_THREADS:-6}" \
  --setenv=QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json \
  --setenv=PYTHONPATH=/home/dev/project/src --setenv=JAVA_TOOL_OPTIONS= \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c30_extract_2.time" \
  /home/dev/project/venvs/queries_from_runs/bin/python -u "$Q/_c30_extract_par.py"
say "C30 EXTRACT stage 2 LAUNCHED unit=notif-c30-extract-2 log=$B/_c30_extract_2.log"
