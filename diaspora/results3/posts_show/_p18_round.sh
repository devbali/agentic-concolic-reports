#!/bin/bash
# P18 — one round: explain the drive just finished, then the checkpointed pass.
#   usage: bash _p18_round.sh <DRIVETAG> <NEXTTAG> <BASELIST>
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
DT="${1:?drivetag}"; NT="${2:?nexttag}"; BL="${3:?baselist}"
say(){ echo "[$(date -Is)] $*"; }
say "EXPLAIN $DT"
cage "p18exp${DT}.scope" 3G \
  env P15_TAG="$DT" P15_SET=A P15_GAPS="$B/_p15_gaps.json" \
      P15_MANIFEST="$B/_p15_manifest.json" \
      PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      python3 -u "$B/_p15_explain.py" > "$B/_p18_explain_${DT}.log" 2>&1
say "explain exit=$?"
sed -n '/dumps labelled/,$p' "$B/_p18_explain_${DT}.log" | head -60
say "PASS $NT (cap 9G, ALONE_OVERRIDE=1)"
ALONE_OVERRIDE=1 PASS_CAP=9G bash "$B/_p15_pass.sh" "$NT" "$DT" "$BL"
