#!/bin/bash
# P26 — CENSUS ONLY (no construct, no drive, no pass). Used once the stop rule
# is one round from being met: the next census is needed to BOOK the previous
# round, but driving another round is exactly what the rule forbids, and the
# full round driver would go straight from S1 to S2. This is S1 alone.
#   usage: bash _p26_census_only.sh <N> <PREVLIST> [WAITLOG] [WAITPAT]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
. "$B/_cage.sh"
N="${1:?usage: _p26_census_only.sh <N> <prevlist> [waitlog] [waitpat]}"
PREV="${2:?prev pruned snapshot}"; [ -f "$PREV" ] || PREV="$B/$PREV"
WAITLOG="${3:-}"; WAITPAT="${4:-}"
L="$B/_p26_census_P26R${N}.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" | tee -a "$L"; }
say "=== P26 CENSUS-ONLY P26R${N} over $(basename "$PREV") ==="
if [ -n "$WAITLOG" ]; then
  w=0
  until grep -qE "$WAITPAT" "$WAITLOG" 2>/dev/null; do
    [ $((w % 600)) -eq 0 ] && say "  stage0: waiting on $(basename "$WAITLOG") (${w}s)"
    sleep 60; w=$((w+60))
  done
  say "stage0 OK"
fi
say "S1 EMIT/CENSUS over $(wc -l < "$PREV") profiles, cap 6G"
cage "p26emit${N}.scope" 6G bash "$B/_p26_emit.sh" "P26R${N}" "$PREV"
EL="$B/_p26_enum_P26R${N}.log"
caged_verdict "p26emit${N}.scope" "$EL" '^P26-EMIT-DONE' | tee -a "$L"
grep -qE '^P26-EMIT-DONE' "$EL" || { say "P26-CENSUS-FAILED"; exit 3; }
grep -E '^universe built|^  sets=|^EMIT: remaining|^  16b:' "$EL" | tee -a "$L"
say "P26-CENSUS-DONE P26R${N}"
