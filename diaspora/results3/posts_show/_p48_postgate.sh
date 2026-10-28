#!/usr/bin/env bash
# P48 POST-GATE — read the verdict, then re-price confinement NON-provisionally.
#
#   usage: _p48_postgate.sh [verdict|reproject|both]   (default: verdict)
#
# STEP 1 — THE VERDICT, BY FIELD, NEVER FROM THE SCROLLBACK.
#
# `coverage_report.py` prints `OVERALL_COMPLETE=` around the completion section
# and that line has repeatedly been stale or preliminary relative to what
# actually landed in the JSON. The verdict is `completion.complete`,
# `completion.blocking` and `assumptions.verdict_counts` IN coverage_summary.json.
# `_p48_verdict.py` reads exactly those, decoding only the sub-objects it prints
# (the file is ~500 MB; a plain json.load costs ~10 GB and this may run beside
# other work).
#
# Also note `sys.exit(main())` returns NON-ZERO whenever complete is False, so
# the unit showing `ExecMainStatus=1` is the DESIGNED outcome of an incomplete
# pass, not a crash. Check `Result=` and the tail of the log, not the code.
#
# STEP 2 — WHY THE CENSUS MUST BE RE-RUN AFTER THE GATE.
#
# The coverage-only pass reported `CONFINEMENT=...PROVISIONAL=True`: every
# declared ConfinementAssumption was APPLIED optimistically, before the gate
# had tested any of it. The 2026-09-26 census priced §16c on that optimistic
# basis and got:
#
#     16b (pre-confinement)  remaining = 2,140,776,534,489
#     16c (confinement ON)   remaining =         3,698,090      (578,887x less)
#
# The gate then REFUTED confinement in bulk — 1,586 ConfinementAssumption FAILs
# by the time stage 2 was half done, 1,523 of them on clause (i) ("flip-A
# changed 20-32 shapes OUTSIDE footprint(A)", almost all naming
# `CollectionProxy.records | Reshare query`). A refuted licence is one the
# projection may no longer use, and the gate feeds those back through
# `_extend_withdrawn_file` into `_confinement_withdrawn_v3.json`.
#
# So 3,698,090 is a LOWER BOUND measured under assumptions that have since been
# refuted. The honest post-gate number comes from re-running the census with
# the withdrawal file the gate just wrote — i.e. with the refuted licences
# removed. THAT number, not the pre-gate one, is what says whether the residue
# is closable by construction.
#
# Do NOT quote 3,698,090 as the post-gate remaining. It is the pre-gate,
# optimistic figure.
#
# HOW TO GET THE POST-GATE NUMBER — and a shared-tool gap found 2026-09-28.
#
# `coverage.restrict_confinement()` DOES take a `withdrawn` argument
# (coverage.py:1797), but `reports/diaspora/tools/confinement_census.py` NEVER
# PASSES IT — it has no reference to withdrawals at all. So re-running the
# census against the gate's withdrawal file would silently reproduce the
# PRE-gate number and look like a confirmation. That is a shared tool, so it is
# FLAGGED, not edited.
#
# The supported path needs no shared change: `coverage_report.py:366` reads
# `WITHDRAWN_PAIRS_FILE`, so re-running the COVERAGE-ONLY pass with the file the
# gate just wrote re-projects confinement with the refuted licences removed and
# reports the post-gate DEMAND_SETS and confinement counts. ~71 min.
#
# NOTE ALSO that THIS gate run's own coverage numbers are still PRE-gate: the
# coverage phase runs BEFORE the assumption gate, so it read the withdrawal file
# while it was still empty; `_extend_withdrawn_file` only writes afterwards.
set -uo pipefail
B=/home/dev/project/reports/diaspora/results3/posts_show
MODE="${1:-verdict}"
cd /home/dev/project

verdict() {
  echo "=== unit ==="
  systemctl --user show p48-fullgate-v3b.service -p Result -p ExecMainStatus -p ActiveState 2>/dev/null
  echo
  echo "=== log tail (the run's own last words) ==="
  tail -25 "$B/_p48_fullgate_v3.log"
  echo
  echo "=== VERDICT, by field, from coverage_summary.json ==="
  python3 "$B/_p48_verdict.py" "$B/coverage_summary.json"
  echo
  echo "=== withdrawal file the gate fed back ==="
  python3 - <<'PY'
import json
p="/home/dev/project/reports/diaspora/results3/posts_show/_confinement_withdrawn_v3.json"
try:
    d=json.load(open(p))
except Exception as e:
    print("  unreadable:", e); raise SystemExit
print(f"  {p}")
print(f"  entries: {len(d)}")
if d:
    s=d[0]
    print(f"  sample: {json.dumps(s)[:300]}")
PY
}

# Re-project coverage with the gate's withdrawals applied. This is the
# supported route (see the note above): the CENSUS tool ignores withdrawals, the
# COVERAGE pass honours them.
reproject() {
  local n
  n=$(python3 -c "import json;print(len(json.load(open('$B/_confinement_withdrawn_v3.json'))))" 2>/dev/null || echo 0)
  echo "=== POST-GATE RE-PROJECTION: $n withdrawn pair(s) will be applied ==="
  if [ "$n" = 0 ]; then
    echo "    NOTE: the withdrawal file is EMPTY. Either the gate refuted nothing"
    echo "    (contradicted by the FAILs in _c1/_gate_engine.log), or the feedback"
    echo "    loop did not fire. Check _extend_withdrawn_file before re-projecting."
  fi
  systemd-run --user --no-block --unit=p48-covonly-postgate --slice=concolic-cov.slice \
    -p MemoryMax=48G -p MemorySwapMax=0 --quiet -p WorkingDirectory=/home/dev/project \
    -p StandardOutput="file:$B/_p48_covonly_postgate.log" \
    -p StandardError="append:$B/_p48_covonly_postgate.log" \
    --setenv=JAVA_TOOL_OPTIONS= \
    /usr/bin/choom -n 1000 -- env \
      DUMP_LIST="$B/_snapshot_v3_20260926.txt" \
      WITHDRAWN_PAIRS_FILE="$B/_confinement_withdrawn_v3.json" \
      NO_PRIOR_FOOTPRINTS=1 \
      FOOTPRINTS_OUT="$B/_p48_POSTGATE_footprints.json" \
      COVERAGE_CHECKPOINT="$B/_p48_POSTGATE_coverage.ckpt.jsonl" \
      SUMMARY_OUT="$B/_cov_P48POSTGATE.json" \
      SKIP_COMPLETION=1 HEARTBEAT_SECS=300 \
      PYTHONPATH=/home/dev/project/src \
      python3 -u "$B/coverage_report.py" \
    && echo "launched p48-covonly-postgate (ARM A WAITER FOR IT)"
}

case "$MODE" in
  verdict) verdict ;;
  census|reproject) reproject ;;
  both)    verdict; echo; reproject ;;
  *) echo "usage: _p48_postgate.sh [verdict|reproject|both]" >&2; exit 2 ;;
esac
