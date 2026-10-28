#!/bin/bash
# =============================================================================
# C23 CONFINEMENT-OFF / PRECISION MEASUREMENT PASS  (2026-09-14)
#
#   usage: bash _c23_pass.sh <TAG>
#
# MEASUREMENT ONLY. Reads the FROZEN C21R1 snapshot (_snapshot_c21_R1.txt,
# 132 524 runs), runs THIS agent's own driver copy `_c23_coverage_report.py`
# (never `coverage_report.py`, which the C22 campaign owns and executes), and
# writes ONLY `_c23_*` files. Nothing is driven, declared, gated or withdrawn.
#
# Same §16e + §16f settings and MAX_MISSING_PER_CLIQUE=1 as _c21_pass_v2.sh.
# Each TAG gets its OWN checkpoint path: the C1 currency fix (CONF_KEEP_NOTES)
# is a LOADER change and is NOT part of the engine's step-6 checkpoint key, so
# sharing a checkpoint across tags would silently replay the wrong footprints.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
TAG="${1:?usage: _c23_pass.sh <TAG>}"
LIST="$B/_snapshot_c21_R1.txt"
[ -f "$LIST" ] || { echo "no snapshot: $LIST"; exit 2; }
CAP="${CAP:-8G}"; CAPMB="${CAPMB:-8192}"
COV_OUT="$B/_c23_cov_${TAG}.json"
COV_CKPT="$B/_c23_cov_${TAG}.ckpt.jsonl"
PAIRS_OUT="$B/_c23_pairs_${TAG}.json"
LOG="$B/_c23_cov_${TAG}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c23.log"; }

say "C23 PASS $TAG  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP"
say "  CONFINEMENT=${CONFINEMENT:-1} CONF_KEYING=${CONF_KEYING:-coevaluated} CONF_SPAN_UNION=${CONF_SPAN_UNION:-0} CONF_KEEP_NOTES=${CONF_KEEP_NOTES:-0}"
say "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
say "  driver _c23_coverage_report.py md5 $(md5sum "$B/_c23_coverage_report.py" | cut -d' ' -f1)"

# ---- HOLDS -----------------------------------------------------------------
# (a) no OTHER endpoint's / campaign's coverage_report.py may run at the same
#     time (coordinator rule 2026-09-13, in force while the posts_show
#     confinement gate runs). Match the script PATH, drop every Claude Code
#     wrapper shell (`shell-snapshots`), and restrict to real python3.
_blockers(){ pgrep -a python3 2>/dev/null | grep -v shell-snapshots \
             | grep -E "(notifications_index|posts_show|comments_index|conversations_index|people_stream)/(coverage_report[.]py|_p3[0-9][_.a-z0-9]*[.]py)"; }
while _blockers >/dev/null; do
  say "C23 PASS $TAG HOLD: coverage_report.py already running -> $(_blockers | head -2 | cut -c1-160)"
  sleep 60
done
# (b) posts_show P3x rounds have priority; the CONTINUOUS confinement gate
#     `posts-p26-gate-v2-*` is NEVER a hold condition and is never stopped.
while systemctl --user list-units --state=active --no-legend 'posts-p3*' 2>/dev/null | grep -q .; do
  say "C23 PASS $TAG WAIT: a posts-p3* unit is active (it has priority)"
  sleep 60
done
# (c) the cage rule: free -g >= 4 AND (live MemoryMax - MemoryCurrent) >= cap
i=0
while :; do
  fg=$(free -g | awk '/^Mem/{print $7}')
  cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value 2>/dev/null); case "$cur" in ''|*[!0-9]*) cur=0;; esac
  mx=$(systemctl --user show concolic-cov.slice -p MemoryMax --value 2>/dev/null); case "$mx" in ''|infinity|*[!0-9]*) mx=4294967296;; esac
  head=$(( (mx - cur) / 1048576 ))
  if [ "${fg:-0}" -ge 4 ] && [ "$head" -ge "$CAPMB" ]; then
    say "C23 PASS $TAG LAUNCH: free=${fg}G cage_headroom=${head}MB cap=${CAPMB}MB"
    break
  fi
  [ $((i % 10)) -eq 0 ] && say "C23 PASS $TAG WAIT: free=${fg}G (need >=4) cage_headroom=${head}MB (need >=${CAPMB}MB)"
  i=$((i+1)); sleep 30
done

systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c23_cov_${TAG}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      SKIP_COMPLETION=1 SUMMARY_OUT="$COV_OUT" \
      COVERAGE_CHECKPOINT="$COV_CKPT" \
      CONF_PAIRS_OUT="$PAIRS_OUT" \
      CONFINEMENT="${CONFINEMENT:-1}" \
      CONF_KEYING="${CONF_KEYING:-coevaluated}" \
      CONF_SPAN_UNION="${CONF_SPAN_UNION:-0}" \
      CONF_KEEP_NOTES="${CONF_KEEP_NOTES:-0}" \
      FORECLOSURE_CONJUNCTIONS=1 \
      FORECLOSURE_SUBCONJUNCTIONS=1 \
      FORECLOSURE_CONJUNCTION_WIDTH=3 \
      MAX_MISSING_PER_CLIQUE=1 \
      MISSING_CAP="${MISSING_CAP:-40000}" \
      HEARTBEAT_SECS=120 \
      python3 -u "$B/_c23_coverage_report.py" > "$LOG" 2>&1
say "C23 PASS $TAG exit=$?"
if grep -qE '^COMPLETE=' "$LOG"; then
  say "VERDICT C23-$TAG: OK (line present)"
  grep -E '^\[coverage\]|^\[confinement\]|^\[foreclosure\]|^(COMPLETE|CONF |GENUINE|CONJ_|SUBCONJ_|dump_errors|wrote)' "$LOG" | tee -a "$B/_c23.log"
  grep -E 'Maximum resident|Elapsed' "$B/_c23_cov_${TAG}.time" | tee -a "$B/_c23.log"
  say "C23-PASS-DONE $TAG -> $COV_OUT / $COV_CKPT"
else
  say "VERDICT C23-$TAG: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_c23.log"
  say "C23-PASS-INCOMPLETE $TAG"
  exit 10
fi
