#!/bin/bash
# PHASE-3 DEMAND ROUND for posts_show — batching at the DRIVER level.
#
# The difference from `_demand_round.sh` (§30): the demand targets come from
# the EXACT ENUMERATOR, not from a checker pass. `_demand_round.sh` needs a
# `coverage_report.py` pass to produce `missing[]` (pass A: 3 h 41 m of solver
# on 14 742 profiles at MMC=4, and MMC caps it at 4 witnesses per set anyway);
# `_exact_enum_emit.py` emits EVERY remaining cube of EVERY demand set in one
# census. The checker pass then runs ONCE, at the end, to CERTIFY.
#
#   enumerate+emit -> root (one seed per cube) -> chunked drive -> re-snapshot
#   -> exact prune -> re-enumerate -> the round's own closed/run rate
#
# usage: _p3_round.sh <TAG> <pruned-snapshot-to-root-from>
# env:   CHUNK (250), DRIVE_PAR (2), EMIT_MAX_PER_SET (0=all), EMIT_CAP (0=all)
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
TAG="$1"; PRUNED="$2"
LOG="$B/_p3round_${TAG}.log"; : > "$LOG"
say(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }

say "=== PHASE-3 ROUND $TAG  pruned=$PRUNED ==="
free -m | sed -n 2p | tee -a "$LOG"

# ---- 1. enumerate + EMIT every remaining cube ------------------------------
EMIT="$B/_enum_emit_${TAG}.json"
say "--- _exact_enum_emit.py (census + emit)"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=5G --unit="pxenum_${TAG}.scope" \
  env DUMP_LIST="$PRUNED" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      EMIT_OUT="$EMIT" EMIT_MAX_PER_SET="${EMIT_MAX_PER_SET:-0}" EMIT_CAP="${EMIT_CAP:-0}" \
      REACH_SPLIT="${REACH_SPLIT:-1}" REACH_OUT="_reach_split_${TAG}.json" \
  python3 -u "$B/_exact_enum_emit.py" --json-out "$B/_enum_${TAG}.json" \
  > "$B/_enum_${TAG}.log" 2>&1
say "enum exit=$?"
grep -E '^EXACT:|^EMIT:|^FORECLOSURE:|tree_missing=|EMIT-MISMATCH|REACHABLE remaining|MULTI-GATE-FORECLOSED|leaf groups:' "$B/_enum_${TAG}.log" | tee -a "$LOG"

# ---- 2. one graph-guided seed per remaining cube ---------------------------
# ROOT_LIST, not $PRUNED. `_demand_root.py` picks each cube's base by SCANNING
# EVERY indexed dump (O(cubes x dumps x conjuncts)); on this endpoint a cube
# carries ~35 conjuncts, so rooting 7 220 cubes against all 31 054 profiles is
# ~8e9 Python operations — hours, for a choice that only needs a base which
# RECORDS the cube's expressions. A stride sample of the same pruned snapshot
# (every 8th profile) gives the same kind of base at an eighth of the cost, and
# it is a stride over a list that is already one-representative-per-profile, so
# it is not a sorted prefix (DISCIPLINE §14).
ROOT_LIST="${ROOT_LIST:-$PRUNED}"
say "rooting bases from $ROOT_LIST ($(wc -l < "$ROOT_LIST") profiles)"
say "--- _demand_root.py (SUMMARY_IN = the enumerator's cubes)"
SUMMARY_IN="$EMIT" DUMP_LIST="$ROOT_LIST" python3 -u "$B/_demand_root.py" >> "$LOG" 2>&1
grep -E 'SUMMARY_IN|missing \(blocking\)|rooted seed dicts|no corpus base|SKIPPED|never minted' "$LOG" | tail -12

# ---- 3. drive the whole batch, chunked, abort-checked ----------------------
say "--- _demand_drive.sh"
DRIVE_PAR="${DRIVE_PAR:-2}" bash "$B/_demand_drive.sh" "$TAG" "${CHUNK:-250}" >> "$LOG" 2>&1
grep -E 'seeds ->|corpus after|abort|toxic|consumed' "$B/_demand_drive_${TAG}.log" | tail -20 | tee -a "$LOG"

# ---- 4. re-snapshot, exact prune ------------------------------------------
say "--- re-snapshot + exact prune"
find "$B" -maxdepth 1 -name 'dump_*.json' | sort > "$B/_snapshot_after_${TAG}.txt"
say "corpus now $(wc -l < "$B/_snapshot_after_${TAG}.txt") dumps"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=3G --unit="pxprune_${TAG}.scope" \
  env DUMP_LIST="$B/_snapshot_after_${TAG}.txt" python3 -u "$B/_prune_corpus.py" \
  --out "$B/_snapshot_pruned_${TAG}.txt" >> "$LOG" 2>&1
say "prune exit=$?  -> $(wc -l < "$B/_snapshot_pruned_${TAG}.txt" 2>/dev/null) profiles"

# ---- 5. RE-ENUMERATE: the round's own verdict -----------------------------
say "--- re-enumerate (the round's verdict; NO checker pass)"
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=5G --unit="pxenumB_${TAG}.scope" \
  env DUMP_LIST="$B/_snapshot_pruned_${TAG}.txt" PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
      REACH_SPLIT="${REACH_SPLIT:-1}" REACH_OUT="_reach_split_after_${TAG}.json" \
  python3 -u "$B/_exact_enum_emit.py" --json-out "$B/_enum_after_${TAG}.json" \
  > "$B/_enum_after_${TAG}.log" 2>&1
say "re-enum exit=$?"
grep -E '^EXACT:|^FORECLOSURE:|tree_missing=|REACHABLE remaining|MULTI-GATE-FORECLOSED|leaf groups:' "$B/_enum_after_${TAG}.log" | tee -a "$LOG"
say "=== ROUND $TAG END ==="
