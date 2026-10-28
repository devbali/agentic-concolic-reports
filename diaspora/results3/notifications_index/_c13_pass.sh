#!/bin/bash
# =============================================================================
# C13 COVERAGE PASS — stage 1 of `_c12_rerun_after_restart.sh`, parameterised.
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
COV_OUT="$B/_cov_C13_${STAMP}.json"
COV_CKPT="$B/_cov_c13_${STAMP}.ckpt.jsonl"
LOG="$B/_c13_cov_${STAMP}.log"
say(){ echo "[$(date -Is)] $*" | tee -a "$B/_c13.log"; }

say "C13 PASS $STAMP  list=$(basename "$LIST") ($(wc -l < "$LIST") runs)  cap=$CAP"
say "  engine coverage.py md5 $(md5sum /home/dev/project/src/concolic_engine/coverage.py | cut -d' ' -f1)"
. "$B/_wait_mem.sh"
wait_mem "$CAPMB" "_c13/coverage-$STAMP" | tee -a "$B/_c13.log"
systemd-run --user --scope --slice=concolic-cov.slice \
  -p MemoryMax="$CAP" -p MemorySwapMax=0 --quiet \
  choom -n 1000 -- /usr/bin/time -v -o "$B/_c13_cov_${STAMP}.time" \
  env DUMP_LIST="$LIST" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      SKIP_COMPLETION=1 SUMMARY_OUT="$COV_OUT" \
      COVERAGE_CHECKPOINT="$COV_CKPT" \
      MAX_MISSING_PER_CLIQUE="${MAX_MISSING_PER_CLIQUE:-1}" \
      MISSING_CAP="${MISSING_CAP:-40000}" \
      python3 -u "$B/coverage_report.py" > "$LOG" 2>&1
say "C13 PASS $STAMP exit=$?"
if grep -qE '^COMPLETE=' "$LOG"; then
  say "VERDICT C13-$STAMP: OK (line present)"
  grep -E '^\[coverage\]|^\[checkpoint\]|^(COMPLETE|GENUINE|dump_errors|wrote)' "$LOG" | tee -a "$B/_c13.log"
  grep -E 'Maximum resident|Elapsed' "$B/_c13_cov_${STAMP}.time" | tee -a "$B/_c13.log"
  say "C13-PASS-DONE $STAMP -> $COV_OUT / $COV_CKPT"
else
  say "VERDICT C13-$STAMP: *** NO VERDICT LINE — TREAT AS KILLED, NOT DONE ***"
  tail -25 "$LOG" | sed 's/^/    /' | tee -a "$B/_c13.log"
  say "C13-PASS-INCOMPLETE $STAMP"
  exit 10
fi
