#!/usr/bin/env bash
# P48 — COVERAGE-ONLY pass over the v2 corpus. The gate to stage 2.
#
#   usage: _p48_covonly.sh <snapshot.txt> [tag]
#
# WHY COVERAGE-ONLY FIRST. The full pass (coverage + assumption gate + audits)
# costs about a day. Coverage alone costs the dump load plus Z3 and answers the
# two questions stage 2 needs:
#   * how many demand sets have gaps, and
#   * WHICH combinations are missing -- the input the `_p*_construct.py` family
#     turns into seed files for `_p44_drive_par.sh` (RUNBOOK Phase 2,
#     "construct runs from Z3 counterexamples; never sample").
# Running the assumption gate before the corpus is known to be worth gating is
# how a day gets spent on a corpus that still needs driving.
#
# v3 VARIANT, 2026-09-26. Identical to _p47_covonly.sh except that every output
# name is _p48_* and the withdrawal file is _confinement_withdrawn_v3.json.
# v3 is a THIRD note generation (B-6: relation_args_where, so every
# `relation.find_by(conditions)` note now carries the finder's own WHERE). A
# withdrawal and a footprint are both statements about a PARTICULAR corpus's
# call-shapes, and B-6 changed call-shapes -- so v2's files are no more valid
# for v3 than the B-4 files were for v2. Fresh names, fresh empty withdrawal.
#
# WITHDRAWN PAIRS START EMPTY -- this is deliberate, see the handoff §5 step 5.
# A withdrawal records a gate refutation against a PARTICULAR corpus. The 564
# pairs in _confinement_withdrawn.json were measured against the B-4 corpus,
# whose footprints were computed from corrupted notes; feeding them back would
# suppress confinement licences the new corpus may well support. The feedback
# loop is automatic now (coverage_report.py::_extend_withdrawn_file), so it
# refills itself from the new corpus's own gate verdicts.
#
# PRIOR FOOTPRINTS ARE DISABLED ON THE FIRST v2 PASS -- same argument as the
# withdrawal file, and it is NOT obvious from the config. The corpus tripwire
# (coverage.py:2760-2768) withdraws any pair this corpus does not confine but
# whose PRIOR footprints were disjoint (i.e. the earlier corpus would have
# confined it):
#
#     pa = prior_footprints.get(a); pb = prior_footprints.get(b)
#     if pa is None or pb is None or (pa & pb): continue
#     withdrawn.append((a, b))
#
# `_prior_footprints.json` holds footprints measured on the B-4 corpus, where
# `call_shape` saw CONFLATED, VALUE-SENSITIVE shapes. Comparing v2 against that
# baseline produces withdrawals that say nothing about v2 -- the old pass
# reported WITHDRAWN_TRIPWIRE=745. The tripwire is conservative (withdrawing
# only ever REDUCES licensing, never adds it), so this is not unsoundness, just
# a large pessimism derived from a corrupted baseline.
#
# So: pass NO prior footprints now, and WRITE v3's own with FOOTPRINTS_OUT.
# Promote that file to _prior_footprints.json deliberately, once, when you want
# a later v2 pass to be tripwired against an earlier v2 pass -- which is the
# contract coverage_report.py states for FOOTPRINTS_OUT ("never over
# _prior_footprints.json unless asked").
#
# CHECKPOINTS ARE FRESH FILENAMES. The old ones are keyed to the old corpus;
# they are kept, never reused and never overwritten.
#
# MEMORY: 48G. Measured on this endpoint: 32G was OOM-killed, peak 36.9G.
set -euo pipefail
SNAP="${1:?usage: _p48_covonly.sh <snapshot.txt> [tag]}"
TAG="${2:-P48COV}"
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project

[ -s "$SNAP" ] || { echo "snapshot $SNAP is empty or missing" >&2; exit 2; }
echo "[$(date -Is)] $TAG: $(wc -l < "$SNAP") dumps from $SNAP"

# An EMPTY withdrawal file, created if absent -- never the old one.
WD="$B/_confinement_withdrawn_v3.json"
[ -f "$WD" ] || echo '[]' > "$WD"

exec env \
  DUMP_LIST="$SNAP" \
  WITHDRAWN_PAIRS_FILE="$WD" \
  NO_PRIOR_FOOTPRINTS=1 \
  FOOTPRINTS_OUT="$B/_p48_${TAG}_footprints.json" \
  COVERAGE_CHECKPOINT="$B/_p48_${TAG}_coverage.ckpt.jsonl" \
  SUMMARY_OUT="$B/_cov_${TAG}.json" \
  SKIP_COMPLETION=1 \
  MAX_MISSING_PER_CLIQUE="${MAX_MISSING_PER_CLIQUE:-4}" \
  HEARTBEAT_SECS=300 \
  JAVA_TOOL_OPTIONS= \
  PYTHONPATH=/home/dev/project/src \
  python3 -u "$B/coverage_report.py"
