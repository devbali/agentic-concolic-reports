#!/bin/bash
# =============================================================================
# C22 COVERAGE PASS — §16f SUB-CONJUNCTION FORECLOSURE (DISCIPLINE §16f, 2026-09-13)
#
#   usage: [FORECLOSURE_CONJUNCTIONS=0|1] bash _c24_pass.sh <dump_list> <stamp>
#
# Same body as _c14_pass.sh (coverage layer only, SKIP_COMPLETION=1 +
# SUMMARY_OUT, checkpointed, MAX_MISSING_PER_CLIQUE=1, judged by its OWN
# `^COMPLETE=` line). The one difference is FORECLOSURE_CONJUNCTIONS, which
# `coverage_report.py` defaults to 1 for THIS endpoint; the engine's own
# default is OFF, and the flag is part of the step-6 checkpoint key, so the
# two settings must not share a checkpoint path (the stamp keeps them apart).
#
# C22 (2026-09-13): identical body to `_c21_pass_v2.sh`, new stamps. The input
# is the C21R1 state — `_confinement_withdrawn.json` at 1 884 pairs (the 78 the
# C20 gate refuted are already in), which is what turned C20R4's
# COMPLETE=True/MISSING=4/BLOCKING=0 into C21R1's
# COMPLETE=False/MISSING=11/BLOCKING=7. This script re-censuses after each
# C22 driving round; a further gate withdrawal re-runs it again.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
if [ "$1" = "--verdict" ]; then
  STAMP="${2:?usage: _c24_pass.sh --verdict <stamp>}"
  LOG="$B/_c24_cov_${STAMP}.log"
  sayv(){ echo "[$(date -Is)] $*" | tee -a "$B/_c24.log"; }
  if grep -qE '^COMPLETE=' "$LOG"; then
    sayv "VERDICT C24-$STAMP: OK (line present)"
    grep -E '^\[coverage\]|^\[foreclosure\]|^\[checkpoint\]|^(COMPLETE|GENUINE|CONJ_|SUBCONJ_|dump_errors|wrote)' "$LOG" | tee -a "$B/_c24.log"
    grep -E 'Maximum resident|Elapsed' "$B/_c24_cov_${STAMP}.time" 2>/dev/null | tee -a "$B/_c24.log"
    sayv "C24-PASS-DONE $STAMP"
    exit 0
  fi
  sayv "VERDICT C24-$STAMP: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_c24.log"
  exit 10
fi
LIST="${1:?usage: _c24_pass.sh <dump_list> <stamp>}"
STAMP="${2:?usage: _c24_pass.sh <dump_list> <stamp>}"
[ -f "$LIST" ] || { echo "no such dump list: $LIST"; exit 2; }
CAP="${CAP:-8G}"; CAPMB="${CAPMB:-8192}"
CONJ="${FORECLOSURE_CONJUNCTIONS:-1}"
# §16f (DISCIPLINE §16f): the SUB-conjunction rule. OFF in the engine and OFF
# in coverage_report.py by default; this script turns it ON, because that is
# the whole point of C20. W caps |C| and is the cost bound. Both are part of
# the step-6 checkpoint key, so a C18 checkpoint is never replayed here (the
# stamp keeps the paths apart anyway).
SUBCONJ="${FORECLOSURE_SUBCONJUNCTIONS:-1}"
CWIDTH="${FORECLOSURE_CONJUNCTION_WIDTH:-3}"
COV_OUT="$B/_cov_C24_${STAMP}.json"
COV_CKPT="$B/_cov_c24_${STAMP}.ckpt.jsonl"
LOG="$B/_c24_cov_${STAMP}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c24.log"; }

say "C24 PASS $STAMP  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP  conj=$CONJ  subconj=$SUBCONJ  W=$CWIDTH"
say "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do
  say "C24 PASS $STAMP WAIT: free<4G"; sleep 30
done
# COORDINATOR RULE (2026-09-13, after the cage hit 19.6G with the posts_show
# confinement gate at 7.9G + two coverage passes): ONE endpoint's
# coverage_report.py on the box at a time while that gate runs. Drives may
# overlap; passes may not. Checked HERE, inside the unit, so a launcher that
# dies cannot skip it.
# NB: `pgrep -f <name>` also matches any SHELL whose command line merely
# MENTIONS the pattern — a polling watcher's argv contains the job name
# BECAUSE it is polling for it, and a fresh watcher spawns every few minutes,
# so a bare-name hold never clears: a LIVELOCK, not a wait. It cost the
# posts_show round 50 minutes on 2026-09-13. TWO defences, both required:
#   * match the script PATH, never a bare job name; and
#   * drop every Claude Code wrapper shell — each carries `shell-snapshots`
#     in its argv and no real job ever does.
# The `pgrep -a python3` restriction is kept on top of both: a pass IS a
# python3 process, and a `python3 -c` one-liner that merely names the path
# would otherwise still match.
_blockers(){ pgrep -a python3 2>/dev/null | grep -v shell-snapshots \
             | grep -E "posts_show/(coverage_report[.]py|_p31[_.a-z0-9]*[.]py)"; }
while _blockers >/dev/null; do
  say "C24 PASS $STAMP HOLD: real posts_show blocker(s) -> $(_blockers | head -2 | cut -c1-140)"
  sleep 60
done
# C22 (2026-09-13): the posts_show P31 round is armed and has priority. Its
# units are `posts-p31-*`; the CONTINUOUS confinement gate
# `posts-p26-gate-v2-20260913` is NOT a hold condition and is never stopped.
while systemctl --user list-units --state=active --no-legend 'posts-p31-*' 2>/dev/null | grep -q .; do
  say "C24 PASS $STAMP WAIT: a posts-p31-* unit is active (P31 has priority)"
  sleep 60
done
wait_mem "$CAPMB" "_c22/coverage-$STAMP" | tee -a "$B/_c24.log"
# C24 (2026-09-14): --no-block --unit, NOT --scope.
# DEFECT FOUND AND FIXED THE SAME ROUND: with --no-block the shell redirection
# `> "$LOG" 2>&1` applies to the systemd-run CLIENT, not to the service, so the
# job's stdout went to the JOURNAL and $LOG stayed 0 bytes — and the verdict
# grep reads $LOG, so a finished pass would have been read as killed. The unit
# now writes the log itself with StandardOutput=file:. A --scope client and a
# BLOCKING --unit client are both killed with the session that launched them
# (two hour-long jobs lost on 2026-09-13); a --no-block --unit job outlives it.
# The wrapper therefore LAUNCHES and returns; the verdict is judged by a second
# invocation (`bash _c24_pass.sh --verdict <stamp>`) or by reading $LOG.
systemd-run --user --no-block --unit="notif-c24-pass-${STAMP}" \
  --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet -p WorkingDirectory="$B" \
  -p StandardOutput="file:$LOG" -p StandardError="append:$LOG" \
  --setenv=DUMP_LIST="$LIST" --setenv=PYTHONPATH=/home/dev/project/src \
  --setenv=JAVA_TOOL_OPTIONS= \
  --setenv=SKIP_COMPLETION=1 --setenv=SUMMARY_OUT="$COV_OUT" \
  --setenv=COVERAGE_CHECKPOINT="$COV_CKPT" \
  --setenv=FORECLOSURE_CONJUNCTIONS="$CONJ" \
  --setenv=FORECLOSURE_SUBCONJUNCTIONS="$SUBCONJ" \
  --setenv=FORECLOSURE_CONJUNCTION_WIDTH="$CWIDTH" \
  --setenv=MAX_MISSING_PER_CLIQUE="${MAX_MISSING_PER_CLIQUE:-1}" \
  --setenv=MISSING_CAP="${MISSING_CAP:-40000}" \
  --setenv=HEARTBEAT_SECS=120 \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c24_cov_${STAMP}.time" \
      python3 -u "$B/coverage_report.py"
say "C24 PASS $STAMP LAUNCHED unit=notif-c24-pass-${STAMP} log=$LOG"
exit 0
if grep -qE '^COMPLETE=' "$LOG"; then
  say "VERDICT C24-$STAMP: OK (line present)"
  grep -E '^\[coverage\]|^\[foreclosure\]|^\[checkpoint\]|^(COMPLETE|GENUINE|CONJ_|SUBCONJ_|dump_errors|wrote)' "$LOG" | tee -a "$B/_c24.log"
  grep -E 'Maximum resident|Elapsed' "$B/_c24_cov_${STAMP}.time" | tee -a "$B/_c24.log"
  say "C24-PASS-DONE $STAMP -> $COV_OUT / $COV_CKPT"
else
  say "VERDICT C24-$STAMP: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_c24.log"
  say "C24-PASS-INCOMPLETE $STAMP"
  exit 10
fi
