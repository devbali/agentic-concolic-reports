#!/bin/bash
# ============================================================================
# P15 CONSTRUCTION DRIVE — posts_show, built from the P14 coverage pass
# (`_cov_FINAL_P14_20260912.json`, COMPLETE=False / NODES=137 / MISSING=5776 /
# PCS=1196750 on `_snapshot_pruned_OD0911.txt`, 32 305 dumps).
#
# READY TO RUN — this script is NOT run by the agent that wrote it.
#
# WHAT IT DRIVES. One seed per P14 gap (RUNBOOK Phase 2: the run is built from
# the checker's counterexample PLUS the enabling gates, never sampled), K bases
# per gap, built by `_p15_construct.py`. Seeds are in
# `_p15_seeds_<variant>.json`; `_p15_manifest.json` maps every seed back to its
# gap id, its base run and why that base was chosen.
#
#   usage:  bash _p15_drive.sh [TAG] [CHUNK]     (defaults: P15A / P15B, 200)
#   env:    SEEDSET   A (default, the 5 776 primary seeds) or B (the backup)
#           DRIVE_PAR (workers this drive runs, default 2)
#           CONCOLIC_SLOTS (machine-wide JRuby locks, default 3)
#
# CAGE. Every JRuby goes through `_cage.sh`'s `cage_drive`, so the drive counts
# against concolic-cov.slice and the launch gate can see it. Each JRuby peaks
# ~1.2 GB (tools/slot); with DRIVE_PAR=2 the cage is set to 4G, which holds two
# VMs plus the driver's own python.
#
# CHECKPOINT — EXPLICIT, BY SEED ID. `_chunk_drive.sh`'s own `done_${V}_${C}`
# marker only exists inside one TAG and is written when the worker finishes, so
# a killed drive that already produced dumps would re-run them. The PRE-PASS
# below closes that: for every (variant, chunk) it COUNTS THE ARTEFACT
# (DISCIPLINE §12) — the dumps labelled `_<TAG><vv><CCCC>r*` — and, when the
# count reaches the chunk's seed count, writes the marker itself and records
# every seed id in that chunk to `_p15_driven_seeds.txt`. The skip is therefore
# stated per seed id, not inferred from a log line, and the drive is resumable
# after any kill.
#
# EXPECTED DURATION. Measured on this batch, round OD0911 (2026-09-11,
# DRIVE_PAR=2, CHUNK=200): 13 080 seeds in 57.5 min end to end = 3.79 runs/s
# overall; the auth_json leg alone ran 9 558 in 35.6 min = 4.48 runs/s, and a
# single 200-seed chunk took 83 s (2.4 runs/s per worker). At 3.8 runs/s:
#     set A, 5 776 seeds  ~= 25 min       set A + set B, 11 552  ~= 51 min
# The script prints its own estimate from the seed counts it finds.
#
# VERDICT. The last line is `P15-DRIVE-DONE ...` (or `P15-DRIVE-INCOMPLETE`).
# `caged_verdict` is applied per leg: a leg that exits without its own
# `CHUNK DRIVE ... END` line is TREATED AS KILLED, NOT DONE.
# ============================================================================
set +e
unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 1
. "$B/_cage.sh"

# SEEDSET A (default) = the PRIMARY batch: one seed per gap on the base that
# covers every alias canonical the cube is spelled with (5 776 seeds, verified
# 5 776/5 776 resolvable). SEEDSET B = the K=2 backup on a second base (another
# 5 776); drive it only if A leaves gaps — 4 862 of its seeds carry one key its
# base cannot resolve to an ordinal, so B is a hedge against the 68 %
# never-REACHED rate OD0911 measured, not a second full attempt.
SET="${SEEDSET:-A}"
case "$SET" in
  A) PREF="_p15_seeds_"  ; DEFTAG="P15A" ;;
  B) PREF="_p15_seedsB_" ; DEFTAG="P15B" ;;
  # 2026-09-12 (round 1, §78): a THIRD form, so a CONSTRUCTED SUBSET can be
  # driven without overwriting either full set. `SEEDSET=BS` reads
  # `_p15_seedsBS_<variant>.json` and `_p15_manifest_BS.json`. It exists
  # because the blanket set B was measured NOT to be justified — only 697 of
  # its 5 776 bases evaluate anything set A's run left never-evaluated — and
  # driving the 697 is the construction attempt those gaps are owed.
  ?*) PREF="_p15_seeds${SET}_" ; DEFTAG="P15${SET}" ;;
  *) echo "SEEDSET must be A, B or a subset label"; exit 2 ;;
esac
MANIFEST="${P15_MANIFEST:-$B/_p15_manifest.json}"
TAG="${1:-$DEFTAG}"
CHUNK="${2:-200}"
export DRIVE_PAR="${DRIVE_PAR:-2}"
export CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-3}"
LOG="$B/_p15_drive_${SET}.log"
LEDGER="$B/_p15_driven_seeds_${SET}.txt"
VARIANTS="auth_html anon_html auth_json anon_json"
say(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }

: >> "$LOG"; : >> "$LEDGER"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "=== P15 DRIVE $TAG  set=$SET ($PREF*)  chunk=$CHUNK  par=$DRIVE_PAR  corpus before: $before ==="

# ---------------------------------------------------------------- pre-flight
missing=0
for V in $VARIANTS; do
  [ -f "$B/${PREF}${V}.json" ] || { say "MISSING SEED FILE ${PREF}${V}.json"; missing=1; }
done
[ -f "$MANIFEST" ] || { say "MISSING $MANIFEST"; missing=1; }
if [ "$missing" = 1 ]; then
  say "P15-DRIVE-INCOMPLETE — run _p15_construct.py first"; exit 2
fi

# ------------------------------------------- PRE-PASS: checkpoint by seed id
python3 - "$B" "$TAG" "$CHUNK" "$LEDGER" "$SET" "$PREF" "$MANIFEST" <<'PY' | tee -a "$LOG"
import glob, json, os, sys
B, TAG, CHUNK, LEDGER, SET, PREF, MANIFEST = (sys.argv[1], sys.argv[2], int(sys.argv[3]),
                                              sys.argv[4], sys.argv[5], sys.argv[6],
                                              sys.argv[7])
man = [m for m in json.load(open(MANIFEST)) if m["seed_set"] == SET]
by = {}
for m in man:
    by.setdefault(m["variant"], {})[m["seed_index"]] = m["gap"]
done_ids, todo, total = [], 0, 0
for V in ("auth_html", "anon_html", "auth_json", "anon_json"):
    seeds = json.load(open(os.path.join(B, f"{PREF}{V}.json")))
    total += len(seeds)
    if not seeds:
        continue
    tag2 = f"{TAG}{V[:2]}{V[5:7]}"
    cd = os.path.join(B, "_chunks", tag2)
    os.makedirs(cd, exist_ok=True)
    nch = (len(seeds) + CHUNK - 1) // CHUNK
    for c in range(nch):
        lo, hi = c * CHUNK, min((c + 1) * CHUNK, len(seeds))
        marker = os.path.join(cd, f"done_{V}_{c:04d}")
        have = len(glob.glob(os.path.join(
            B, f"dump_{V}*_{tag2}{V[:2]}{V[5:7]}{c:04d}r*.json")))
        if have >= (hi - lo) and not os.path.exists(marker):
            open(marker, "w").close()
        if os.path.exists(marker):
            done_ids += [by.get(V, {}).get(i, f"{V}#{i}") for i in range(lo, hi)]
        else:
            todo += hi - lo
    print(f"  {V}: {len(seeds)} seeds / {nch} chunks")
with open(LEDGER, "a") as fh:
    for g in done_ids:
        fh.write(g + "\n")
print(f"  CHECKPOINT: {len(done_ids)} seed ids already driven (skipped by id, "
      f"ledger {os.path.basename(LEDGER)}); {todo} of {total} remain")
print(f"  ESTIMATE:   {todo} runs at 3.8 runs/s (OD0911 measured) = "
      f"{todo/3.8/60:.0f} min; JRuby peaks ~1.2 GB each, {os.environ.get('DRIVE_PAR','2')} in parallel")
PY

# ------------------------------------------------------------------ the legs
for V in $VARIANTS; do
  F="$B/${PREF}${V}.json"
  N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
  [ "$N" = 0 ] && { say "$V: 0 seeds — nothing to drive (stated, not silent)"; continue; }
  TAG2="${TAG}${V:0:2}${V:5:2}"
  say "$V: $N seeds -> _chunk_drive.sh (tag $TAG2)"
  cage_drive "p15drv${SET}${V:0:2}${V:5:2}" 4G \
    bash "$B/_chunk_drive.sh" "$F" "$TAG2" "$CHUNK" "$V" >> "$LOG" 2>&1
  caged_verdict "p15drv${SET}${V:0:2}${V:5:2}" "$B/_chunk_drive_${TAG2}.log" \
    "=== CHUNK DRIVE $TAG2 END ===" | tee -a "$LOG"
done

after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "corpus after: $after (+$((after-before)))"
left=$(python3 - "$B" "$TAG" "$CHUNK" "$PREF" <<'PY'
import glob, json, os, sys
B, TAG, CHUNK, PREF = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
n = 0
for V in ("auth_html", "anon_html", "auth_json", "anon_json"):
    seeds = json.load(open(os.path.join(B, f"{PREF}{V}.json")))
    tag2 = f"{TAG}{V[:2]}{V[5:7]}"
    cd = os.path.join(B, "_chunks", tag2)
    for c in range((len(seeds) + CHUNK - 1) // CHUNK):
        if not os.path.exists(os.path.join(cd, f"done_{V}_{c:04d}")):
            n += min((c + 1) * CHUNK, len(seeds)) - c * CHUNK
print(n)
PY
)
if [ "$left" = 0 ]; then
  say "P15-DRIVE-DONE $TAG  +$((after-before)) dumps  0 seeds left"
else
  say "P15-DRIVE-INCOMPLETE $TAG  +$((after-before)) dumps  $left seeds left — rerun this script, it resumes by seed id"
fi
