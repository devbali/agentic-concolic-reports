#!/bin/bash
# =============================================================================
# C15 COVERAGE PASS — §16e CONJUNCTION FORECLOSURE (DISCIPLINE §16e, 2026-09-13)
#
#   usage: [FORECLOSURE_CONJUNCTIONS=0|1] bash _c15_pass.sh <dump_list> <stamp>
#
# Same body as _c14_pass.sh (coverage layer only, SKIP_COMPLETION=1 +
# SUMMARY_OUT, checkpointed, MAX_MISSING_PER_CLIQUE=1, judged by its OWN
# `^COMPLETE=` line). The one difference is FORECLOSURE_CONJUNCTIONS, which
# `coverage_report.py` defaults to 1 for THIS endpoint; the engine's own
# default is OFF, and the flag is part of the step-6 checkpoint key, so the
# two settings must not share a checkpoint path (the stamp keeps them apart).
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
LIST="${1:?usage: _c15_pass.sh <dump_list> <stamp>}"
STAMP="${2:?usage: _c15_pass.sh <dump_list> <stamp>}"
[ -f "$LIST" ] || { echo "no such dump list: $LIST"; exit 2; }
CAP="${CAP:-8G}"; CAPMB="${CAPMB:-8192}"
CONJ="${FORECLOSURE_CONJUNCTIONS:-1}"
COV_OUT="$B/_cov_C15_${STAMP}.json"
COV_CKPT="$B/_cov_c15_${STAMP}.ckpt.jsonl"
LOG="$B/_c15_cov_${STAMP}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c15.log"; }

say "C15 PASS $STAMP  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP  conj=$CONJ"
say "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do
  say "C15 PASS $STAMP WAIT: free<4G"; sleep 30
done
wait_mem "$CAPMB" "_c15/coverage-$STAMP" | tee -a "$B/_c15.log"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c15_cov_${STAMP}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      SKIP_COMPLETION=1 SUMMARY_OUT="$COV_OUT" \
      COVERAGE_CHECKPOINT="$COV_CKPT" \
      FORECLOSURE_CONJUNCTIONS="$CONJ" \
      MAX_MISSING_PER_CLIQUE="${MAX_MISSING_PER_CLIQUE:-1}" \
      MISSING_CAP="${MISSING_CAP:-40000}" \
      HEARTBEAT_SECS=120 \
      python3 -u "$B/coverage_report.py" > "$LOG" 2>&1
say "C15 PASS $STAMP exit=$?"
if grep -qE '^COMPLETE=' "$LOG"; then
  say "VERDICT C15-$STAMP: OK (line present)"
  grep -E '^\[coverage\]|^\[foreclosure\]|^\[checkpoint\]|^(COMPLETE|GENUINE|CONJ_|dump_errors|wrote)' "$LOG" | tee -a "$B/_c15.log"
  grep -E 'Maximum resident|Elapsed' "$B/_c15_cov_${STAMP}.time" | tee -a "$B/_c15.log"
  say "C15-PASS-DONE $STAMP -> $COV_OUT / $COV_CKPT"
else
  say "VERDICT C15-$STAMP: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_c15.log"
  say "C15-PASS-INCOMPLETE $STAMP"
  exit 10
fi
