#!/bin/bash
# P44 PARALLEL DRIVE — the four scenario legs run CONCURRENTLY and the TOTAL
# JRuby width is sized to the box, not per leg.
#
#   usage: bash _p44_drive_par.sh <SEEDSET> <TAG> <CHUNK> <TOTAL_WIDTH>
#
# Width is split across the legs in proportion to their seed counts (min 1 for
# a non-empty leg), so a 14-seed leg never holds 3 workers while a 2 170-seed
# leg holds 5. `CONCOLIC_SLOTS` is set to the TOTAL so `tools/slot` does not
# serialise the legs against each other.
#
# MEMORY. Each JRuby peaks ~1.2 GB measured on this batch. The caller sizes the
# unit's MemoryMax; this script prints the arithmetic it is relying on so an
# over-parallelised launch is visible BEFORE it OOMs (an earlier round in this
# campaign was OOM-killed because `cage_drive` hard-caps a leg at 4G and
# DRIVE_PAR=7 exceeded it -- this script does not use `cage_drive` at all, it
# runs inside ONE unit whose cap the caller states).
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project || exit 1
SET="${1:?seedset}"; TAG="${2:?tag}"; CHUNK="${3:-150}"; W="${4:-12}"
L="$B/_p44_drive_${TAG}.log"
say(){ echo "[$(date -Is)] $*" >> "$L"; }
export CONCOLIC_SLOTS="$W"
VARIANTS="auth_html anon_html auth_json anon_json"
declare -A NS; TOT=0
for V in $VARIANTS; do
  F="$B/_p15_seeds${SET}_${V}.json"
  n=0; [ -f "$F" ] && n=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
  NS[$V]=$n; TOT=$((TOT+n))
done
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "=== P44 PAR DRIVE $TAG set=$SET chunk=$CHUNK TOTAL_WIDTH=$W seeds=$TOT corpus=$before ==="
say "    memory arithmetic: $W JRuby x ~1.2 GB = ~$((W*12/10)) GB peak, plus the drivers"
START=$(date +%s)
pids=""
for V in $VARIANTS; do
  n=${NS[$V]}
  [ "$n" = 0 ] && { say "$V: 0 seeds (stated, not silent)"; continue; }
  p=$(( (W * n + TOT - 1) / TOT )); [ "$p" -lt 1 ] && p=1
  say "$V: $n seeds, DRIVE_PAR=$p"
  DRIVE_PAR="$p" bash "$B/_chunk_drive.sh" "$B/_p15_seeds${SET}_${V}.json" \
      "${TAG}${V:0:2}${V:5:2}" "$CHUNK" "$V" >> "$L" 2>&1 &
  pids="$pids $!"
done
for pid in $pids; do wait "$pid"; done
END=$(date +%s)
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
d=$((after-before)); w=$((END-START)); [ "$w" = 0 ] && w=1
say "P44-PAR-DRIVE-DONE $TAG width=$W dumps=+$d wall=${w}s RATE=$(python3 -c "print(f'{$d/$w:.2f}')") runs/s"
