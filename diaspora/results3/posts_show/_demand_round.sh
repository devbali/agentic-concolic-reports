#!/bin/bash
# ONE FULL DEMAND ROUND for posts_show, end to end:
#   summary -> rooted seeds -> chunked drive -> re-snapshot -> exact prune -> §16b pass
# so the overnight loop is one command and every step's own verdict is printed.
#
# usage: _demand_round.sh <TAG> <summary.json to root from>
# env:   DRIVE_PAR (default 2), CHUNK (default 250), MMC (MAX_MISSING_PER_CLIQUE)
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
TAG="$1"; SUM="${2:-$B/coverage_summary.json}"
LOG="$B/_round_${TAG}.log"; : > "$LOG"
say(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }

say "=== ROUND $TAG  rooting from $SUM ==="
free -g | head -2 | tee -a "$LOG"

# _demand_root.py reads coverage_summary.json by name. Point it at the pass we
# mean, without pretending a scratch summary is the shipped one.
if [ "$SUM" != "$B/coverage_summary.json" ]; then
  cp "$B/coverage_summary.json" "$B/coverage_summary.json.bak_$TAG" 2>/dev/null
  cp "$SUM" "$B/coverage_summary.json"
  say "staged $SUM as coverage_summary.json (previous kept as .bak_$TAG)"
fi

# The SAME fixed snapshot the pass measured, so a root is built from a dump the
# witness actually saw.
SNAP="$B/_snapshot_round_${TAG}.txt"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$SNAP"
say "snapshot: $(wc -l < "$SNAP") dumps"

say "--- _demand_root.py"
DUMP_LIST="$SNAP" python3 -u "$B/_demand_root.py" >> "$LOG" 2>&1
grep -E 'missing \(blocking\)|rooted seed dicts|no corpus base|SKIPPED|never minted' "$LOG" | tail -12

say "--- _demand_drive.sh"
DRIVE_PAR="${DRIVE_PAR:-2}" bash "$B/_demand_drive.sh" "$TAG" "${CHUNK:-250}" >> "$LOG" 2>&1
tail -4 "$B/_demand_drive_${TAG}.log" | tee -a "$LOG"

say "--- re-snapshot + exact prune"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_after_${TAG}.txt"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=2G --unit="pxprune_${TAG}.scope" \
  env DUMP_LIST="$B/_snapshot_after_${TAG}.txt" python3 -u "$B/_prune_corpus.py" \
  --out "$B/_snapshot_pruned_${TAG}.txt" >> "$LOG" 2>&1
grep 'distinct outcome profiles' "$LOG" | tail -1

say "--- §16b pass"
free -g | head -2 | tee -a "$LOG"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=6G --unit="pxcov_${TAG}.scope" \
  env DUMP_LIST="$B/_snapshot_pruned_${TAG}.txt" SUMMARY_OUT="$B/_cov_${TAG}.json" \
      SKIP_COMPLETION=1 MAX_MISSING_PER_CLIQUE="${MMC:-8}" \
  python3 -u "$B/coverage_report.py" > "$B/_cov_${TAG}.log" 2>&1
say "pass exit=$?"
grep -E '^(COMPLETE|GENUINE|DEMAND_SETS|dumps_loaded|peak RSS)' "$B/_cov_${TAG}.log" | tee -a "$LOG"
grep -c 'TREE-MISSING' "$B/_cov_${TAG}.log" | sed 's/^/TREE_MISSING lines: /' | tee -a "$LOG"
say "=== ROUND $TAG END ==="
