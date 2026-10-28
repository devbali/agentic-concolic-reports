#!/bin/bash
# =============================================================================
# C21 COVERAGE PASS — §16f SUB-CONJUNCTION FORECLOSURE (DISCIPLINE §16f, 2026-09-13)
#
#   usage: [FORECLOSURE_CONJUNCTIONS=0|1] bash _c21_pass.sh <dump_list> <stamp>
#
# Same body as _c14_pass.sh (coverage layer only, SKIP_COMPLETION=1 +
# SUMMARY_OUT, checkpointed, MAX_MISSING_PER_CLIQUE=1, judged by its OWN
# `^COMPLETE=` line). The one difference is FORECLOSURE_CONJUNCTIONS, which
# `coverage_report.py` defaults to 1 for THIS endpoint; the engine's own
# default is OFF, and the flag is part of the step-6 checkpoint key, so the
# two settings must not share a checkpoint path (the stamp keeps them apart).
#
# C21 (2026-09-13): identical body, new stamps. The ONE substantive difference
# from C20 is the INPUT, not the script: `_confinement_withdrawn.json` now
# carries the 78 pairs the C20 assumption gate REFUTED (1 806 -> 1 884), so
# this pass is the re-census DISCIPLINE §16c owes after a gate withdrawal.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
LIST="${1:?usage: _c21_pass.sh <dump_list> <stamp>}"
STAMP="${2:?usage: _c21_pass.sh <dump_list> <stamp>}"
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
COV_OUT="$B/_cov_C21_${STAMP}.json"
COV_CKPT="$B/_cov_c21_${STAMP}.ckpt.jsonl"
LOG="$B/_c21_cov_${STAMP}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c21.log"; }

say "C21 PASS $STAMP  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP  conj=$CONJ  subconj=$SUBCONJ  W=$CWIDTH"
say "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
. "$B/_wait_mem.sh"
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do
  say "C21 PASS $STAMP WAIT: free<4G"; sleep 30
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
  say "C21 PASS $STAMP HOLD: real posts_show blocker(s) -> $(_blockers | head -2 | cut -c1-140)"
  sleep 60
done
# C21 (2026-09-13): the posts_show P31 round is armed and has priority. Its
# units are `posts-p31-*`; the CONTINUOUS confinement gate
# `posts-p26-gate-v2-20260913` is NOT a hold condition and is never stopped.
while systemctl --user list-units --state=active --no-legend 'posts-p31-*' 2>/dev/null | grep -q .; do
  say "C21 PASS $STAMP WAIT: a posts-p31-* unit is active (P31 has priority)"
  sleep 60
done
wait_mem "$CAPMB" "_c21/coverage-$STAMP" | tee -a "$B/_c21.log"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c21_cov_${STAMP}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      SKIP_COMPLETION=1 SUMMARY_OUT="$COV_OUT" \
      COVERAGE_CHECKPOINT="$COV_CKPT" \
      FORECLOSURE_CONJUNCTIONS="$CONJ" \
      FORECLOSURE_SUBCONJUNCTIONS="$SUBCONJ" \
      FORECLOSURE_CONJUNCTION_WIDTH="$CWIDTH" \
      MAX_MISSING_PER_CLIQUE="${MAX_MISSING_PER_CLIQUE:-1}" \
      MISSING_CAP="${MISSING_CAP:-40000}" \
      HEARTBEAT_SECS=120 \
      python3 -u "$B/coverage_report.py" > "$LOG" 2>&1
say "C21 PASS $STAMP exit=$?"
if grep -qE '^COMPLETE=' "$LOG"; then
  say "VERDICT C21-$STAMP: OK (line present)"
  grep -E '^\[coverage\]|^\[foreclosure\]|^\[checkpoint\]|^(COMPLETE|GENUINE|CONJ_|SUBCONJ_|dump_errors|wrote)' "$LOG" | tee -a "$B/_c21.log"
  grep -E 'Maximum resident|Elapsed' "$B/_c21_cov_${STAMP}.time" | tee -a "$B/_c21.log"
  say "C21-PASS-DONE $STAMP -> $COV_OUT / $COV_CKPT"
else
  say "VERDICT C21-$STAMP: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_c21.log"
  say "C21-PASS-INCOMPLETE $STAMP"
  exit 10
fi
