#!/bin/bash
# =============================================================================
# C13 CONSTRUCTION DRIVE — notifications_index, built from the C12 coverage pass
# (`_cov_FINAL_C12_20260912.json`: COMPLETE=False / NODES=441 / MISSING=781 /
# PCS=7234929 on `_snapshot_pruned_20260911_143539.txt`, 114 610 runs).
#
# One seed per DISTINCT WITNESS LEAF of that pass (777 of them over the 298
# demand sets that have a gap), built by `_c13_construct.py` from the checker's
# own counterexample PLUS the leaf's gate outcomes — read off the checker's
# structure, never re-solved (RUNBOOK Phase 2, construct-not-sample).
#
#   usage:  bash _c13_drive.sh [TAG] [CHUNK]      defaults: C13A / C13B, 200
#   env:    SEEDSET   A (default) or B (the second base per gap)
#           DRIVE_PAR workers this drive runs (default 2 — the cage is SHARED
#                     with posts_show's campaign and two engine services)
#           CONCOLIC_SLOTS machine-wide JRuby locks (default 3)
#
# CAGE. `_chunk_drive.sh`'s worker puts every JRuby in a
# `concolic-cov.slice` scope at JRUBY_CAP (default 2G) and calls `wait_mem`
# before each launch, so this drive is visible to every other launch gate.
#
# CHECKPOINT — BY SEED ID. `_chunk_drive.sh`'s `done_${V}_${C}` marker only
# exists inside one TAG and is written when the worker finishes, so a killed
# drive that already produced dumps would re-run them. The pre-pass below counts
# the ARTEFACT per (variant, chunk) — dumps labelled `_<TAG><vvv><s><CCCC>r*` —
# writes the marker itself when a chunk is already complete, and records every
# skipped seed id in `_c13_driven_seeds_<SET>.txt`.
#
# VERDICT. Last line is `C13-DRIVE-DONE ...` or `C13-DRIVE-INCOMPLETE <n> ...`.
# Per leg, a `_chunk_drive.sh` run without its own `=== CHUNK DRIVE <tag> END`
# line is TREATED AS KILLED, NOT DONE.
# =============================================================================
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd /home/dev/project || exit 1
SET="${SEEDSET:-A}"
case "$SET" in
  A) PREF="${C13_PREF_A:-_c13_seeds_}"  ; DEFTAG="C13A" ;;
  B) PREF="${C13_PREF_B:-_c13_seedsB_}" ; DEFTAG="C13B" ;;
  *) echo "SEEDSET must be A or B"; exit 2 ;;
esac
MANIFEST="${C13_MANIFEST:-_c13_manifest.json}"
TAG="${1:-$DEFTAG}"; CHUNK="${2:-200}"
export DRIVE_PAR="${DRIVE_PAR:-2}"
export CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-3}"
LOG="$B/_c13_drive_${TAG}.log"
LEDGER="$B/_c13_driven_seeds_${TAG}.txt"
VARIANTS="html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain"
say(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }
: >> "$LOG"; : >> "$LEDGER"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "=== C13 DRIVE $TAG set=$SET ($PREF*) chunk=$CHUNK par=$DRIVE_PAR corpus before: $before ==="

missing=0
for V in $VARIANTS; do
  [ -f "$B/${PREF}${V}.json" ] || { say "MISSING SEED FILE ${PREF}${V}.json"; missing=1; }
done
[ -f "$B/$MANIFEST" ] || { say "MISSING $MANIFEST"; missing=1; }
[ "$missing" = 1 ] && { say "C13-DRIVE-INCOMPLETE — run _c13_construct.py first"; exit 2; }

python3 - "$B" "$TAG" "$CHUNK" "$LEDGER" "$SET" "$PREF" "$MANIFEST" <<'PY' | tee -a "$LOG"
import glob, json, os, sys
B, TAG, CHUNK, LEDGER, SET, PREF, MANIFEST = (sys.argv[1], sys.argv[2], int(sys.argv[3]),
                                    sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7])
man = [m for m in json.load(open(os.path.join(B, MANIFEST)))
       if m["seed_set"] == SET]
by = {}
for m in man:
    by.setdefault(m["variant"], {})[m["seed_index"]] = m["gap"]
done_ids, todo, total = [], 0, 0
for V in ("html_plain", "html_typed", "json_plain", "json_typed",
          "mobile_plain", "mobile_typed", "xml_plain"):
    seeds = json.load(open(os.path.join(B, f"{PREF}{V}.json")))
    total += len(seeds)
    if not seeds:
        continue
    sfx = "t" if V.endswith("typed") else "p"
    cd = os.path.join(B, "_chunks", TAG)
    os.makedirs(cd, exist_ok=True)
    nch = (len(seeds) + CHUNK - 1) // CHUNK
    for c in range(nch):
        lo, hi = c * CHUNK, min((c + 1) * CHUNK, len(seeds))
        marker = os.path.join(cd, f"done_{V}_{c:04d}")
        have = len(glob.glob(os.path.join(
            B, f"dump_{V}*_{TAG}{V[:3]}{sfx}{c:04d}r*.json")))
        if have >= (hi - lo) and not os.path.exists(marker):
            open(marker, "w").close()
        if os.path.exists(marker):
            done_ids += [by.get(V, {}).get(i, f"{V}#{i}") for i in range(lo, hi)]
        else:
            todo += hi - lo
    print(f"  {V:13s}: {len(seeds):5d} seeds / {nch} chunks")
with open(LEDGER, "a") as fh:
    for g in done_ids:
        fh.write(g + "\n")
print(f"  CHECKPOINT: {len(done_ids)} seed ids already driven (skipped BY ID, "
      f"ledger {os.path.basename(LEDGER)}); {todo} of {total} remain")
print(f"  ESTIMATE:   {todo} runs at ~3.8 runs/s = {todo/3.8/60:.0f} min")
PY

for V in $VARIANTS; do
  F="$B/${PREF}${V}.json"
  N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
  [ "$N" = 0 ] && { say "$V: 0 seeds — nothing to drive (stated, not silent)"; continue; }
  say "$V: $N seeds -> _chunk_drive.sh (tag $TAG)"
  bash "$B/_chunk_drive.sh" "$F" "$TAG" "$CHUNK" "$V" >> "$LOG" 2>&1
  if grep -q "=== CHUNK DRIVE $TAG END ===" "$B/_chunk_drive_${TAG}.log"; then
    say "  leg $V: END line present"
  else
    say "  leg $V: *** NO END LINE — TREATED AS KILLED, NOT DONE ***"
  fi
done

after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "corpus after: $after (+$((after-before)))"
left=$(python3 - "$B" "$TAG" "$CHUNK" "$PREF" <<'PY'
import json, os, sys
B, TAG, CHUNK, PREF = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
n = 0
for V in ("html_plain", "html_typed", "json_plain", "json_typed",
          "mobile_plain", "mobile_typed", "xml_plain"):
    seeds = json.load(open(os.path.join(B, f"{PREF}{V}.json")))
    cd = os.path.join(B, "_chunks", TAG)
    for c in range((len(seeds) + CHUNK - 1) // CHUNK):
        if not os.path.exists(os.path.join(cd, f"done_{V}_{c:04d}")):
            n += min((c + 1) * CHUNK, len(seeds)) - c * CHUNK
print(n)
PY
)
if [ "$left" = 0 ]; then
  say "C13-DRIVE-DONE $TAG  +$((after-before)) dumps  0 seeds left"
else
  say "C13-DRIVE-INCOMPLETE $TAG  +$((after-before)) dumps  $left seeds left — rerun, it resumes by seed id"
fi
