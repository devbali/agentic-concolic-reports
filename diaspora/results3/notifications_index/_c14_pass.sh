#!/bin/bash
# =============================================================================
# C14 COVERAGE PASS (same body as _c13_pass.sh, C14-named artefacts) — stage 1 of `_c12_rerun_after_restart.sh`, parameterised.
#
#   usage: bash _c13_pass.sh <dump_list> <stamp>
#
# Coverage layer ONLY (SKIP_COMPLETION=1 + SUMMARY_OUT): a gate failure can no
# longer take the coverage numbers with it (C11, 2026-09-11). CHECKPOINTED
# (RUNBOOK §4): re-running with the same stamp resumes and skips every demand
# set already recorded. Judged by its OWN verdict line `^COMPLETE=`; without it
# the pass was KILLED, not done.
#
# MAX_MISSING_PER_CLIQUE=1. The brief said "no MAX_MISSING_PER_CLIQUE", on the
# strength of the engine's new default (DISCIPLINE §16d, 2026-09-12). That is
# NOT what this batch would get: `coverage_report.py:519` reads
# `os.environ.get("MAX_MISSING_PER_CLIQUE", "4")`, so an unset variable means
# FOUR here, and C12 therefore ran at 4 (measured: 171 of its 298 flagged sets
# stopped AT the cap, and the checkpoint holds 885 witnesses, not 298). One
# witness per set is all the constructor needs, so it is set explicitly.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
LIST="${1:?usage: _c13_pass.sh <dump_list> <stamp>}"
STAMP="${2:?usage: _c13_pass.sh <dump_list> <stamp>}"
[ -f "$LIST" ] || { echo "no such dump list: $LIST"; exit 2; }
CAP="${CAP:-8G}"; CAPMB="${CAPMB:-8192}"
COV_OUT="$B/_cov_C14_${STAMP}.json"
COV_CKPT="$B/_cov_c14_${STAMP}.ckpt.jsonl"
LOG="$B/_c14_cov_${STAMP}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c14.log"; }

say "C14 PASS $STAMP  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP"
say "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
. "$B/_wait_mem.sh"
# C14 launch rule: free -g >= 4 on top of _wait_mem's own gate
while [ "$(free -g | awk '/^Mem/{print $7}')" -lt 4 ]; do
  say "C14 PASS $STAMP WAIT: free<4G"; sleep 30
done
wait_mem "$CAPMB" "_c14/coverage-$STAMP" | tee -a "$B/_c14.log"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c14_cov_${STAMP}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      SKIP_COMPLETION=1 SUMMARY_OUT="$COV_OUT" \
      COVERAGE_CHECKPOINT="$COV_CKPT" \
      MAX_MISSING_PER_CLIQUE="${MAX_MISSING_PER_CLIQUE:-1}" \
      MISSING_CAP="${MISSING_CAP:-40000}" \
      python3 -u "$B/coverage_report.py" > "$LOG" 2>&1
say "C14 PASS $STAMP exit=$?"
if grep -qE '^COMPLETE=' "$LOG"; then
  say "VERDICT C14-$STAMP: OK (line present)"
  grep -E '^\[coverage\]|^\[checkpoint\]|^(COMPLETE|GENUINE|dump_errors|wrote)' "$LOG" | tee -a "$B/_c14.log"
  grep -E 'Maximum resident|Elapsed' "$B/_c14_cov_${STAMP}.time" | tee -a "$B/_c14.log"
  say "C14-PASS-DONE $STAMP -> $COV_OUT / $COV_CKPT"
else
  say "VERDICT C14-$STAMP: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_c14.log"
  say "C14-PASS-INCOMPLETE $STAMP"
  exit 10
fi
