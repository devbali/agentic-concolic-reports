#!/bin/bash
# P44 -- the full §16b LEAF enumeration (CENSUS_MODES=enum), never completed
# per the handover. The sustain loop's sample source (_p31_emit_P35.jsonl,
# 470,320 cubes / 730 of 998 sets) is NOT the full residue (838,963 cubes /
# 1,008 sets per the fresh prod census _p31_emit_P44D). This produces the
# honest, complete per-leaf target list so the drive can eventually reach
# the whole residue, not just the 730-set subset. Reuses the UNION2 pruned
# snapshot (87,663 profiles, built minutes ago) instead of re-pruning.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
CENSUS_MODES=enum EMIT_CAP_MEM=24G P31_SKIP_ONEPASS=1 \
  WITHDRAWN_PAIRS="$B/_confinement_withdrawn.json" \
  bash "$B/_p35_emit.sh" P44ENUM "$B/_snapshot_pruned_UNION2.txt"
echo "P44-ENUM-RUN-DONE rc=$?"
