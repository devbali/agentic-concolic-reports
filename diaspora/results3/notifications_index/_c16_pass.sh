#!/bin/bash
# =============================================================================
# C16 COVERAGE PASS — §16e CONJUNCTION FORECLOSURE (DISCIPLINE §16e, 2026-09-13)
#
#   usage: [FORECLOSURE_CONJUNCTIONS=0|1] bash _c16_pass.sh <dump_list> <stamp>
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
LIST="${1:?usage: _c16_pass.sh <dump_list> <stamp>}"
STAMP="${2:?usage: _c16_pass.sh <dump_list> <stamp>}"
[ -f "$LIST" ] || { echo "no such dump list: $LIST"; exit 2; }
CAP="${CAP:-8G}"; CAPMB="${CAPMB:-8192}"
CONJ="${FORECLOSURE_CONJUNCTIONS:-1}"
COV_OUT="$B/_cov_C16_${STAMP}.json"
COV_CKPT="$B/_cov_c16_${STAMP}.ckpt.jsonl"
LOG="$B/_c16_cov_${STAMP}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c16.log"; }

say "C16 PASS $STAMP  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP  conj=$CONJ"
say "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do
  say "C16 PASS $STAMP WAIT: free<4G"; sleep 30
done
# COORDINATOR RULE (2026-09-13, after the cage hit 19.6G with the posts_show
# confinement gate at 7.9G + two coverage passes): ONE endpoint's
# coverage_report.py on the box at a time while that gate runs. Drives may
# overlap; passes may not. Checked HERE, inside the unit, so a launcher that
# dies cannot skip it.
# NB: `pgrep -f <path>` also matches any SHELL whose command line merely
# MENTIONS the path — the coordinator's own posts_show monitor does, and it
# deadlocked this gate for 4 minutes on 2026-09-13. Restrict the match to
# actual python3 processes, which is what a pass is.
while pgrep -a python3 2>/dev/null | grep -q "posts_show/coverage_report[.]py"; do
  say "C16 PASS $STAMP WAIT: posts_show/coverage_report.py is running (one pass at a time)"
  sleep 60
done
wait_mem "$CAPMB" "_c16/coverage-$STAMP" | tee -a "$B/_c16.log"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c16_cov_${STAMP}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      SKIP_COMPLETION=1 SUMMARY_OUT="$COV_OUT" \
      COVERAGE_CHECKPOINT="$COV_CKPT" \
      FORECLOSURE_CONJUNCTIONS="$CONJ" \
      MAX_MISSING_PER_CLIQUE="${MAX_MISSING_PER_CLIQUE:-1}" \
      MISSING_CAP="${MISSING_CAP:-40000}" \
      HEARTBEAT_SECS=120 \
      python3 -u "$B/coverage_report.py" > "$LOG" 2>&1
say "C16 PASS $STAMP exit=$?"
if grep -qE '^COMPLETE=' "$LOG"; then
  say "VERDICT C16-$STAMP: OK (line present)"
  grep -E '^\[coverage\]|^\[foreclosure\]|^\[checkpoint\]|^(COMPLETE|GENUINE|CONJ_|dump_errors|wrote)' "$LOG" | tee -a "$B/_c16.log"
  grep -E 'Maximum resident|Elapsed' "$B/_c16_cov_${STAMP}.time" | tee -a "$B/_c16.log"
  say "C16-PASS-DONE $STAMP -> $COV_OUT / $COV_CKPT"
else
  say "VERDICT C16-$STAMP: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_c16.log"
  say "C16-PASS-INCOMPLETE $STAMP"
  exit 10
fi
