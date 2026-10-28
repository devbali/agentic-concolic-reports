#!/bin/bash
# Drive the ENABLING-CONSTRAINT roots (_enableR_<variant>.json), chunked.
#
# Same shape as _chunk_drive.sh (one JRuby per CHUNK, so a native abort costs
# at most one chunk and the worker resumes past the toxic seed) but the seed
# lists are PER VARIANT: a cube's exprs are only recorded in some variants, so
# _enable_root.py already decided which variants each seed is for. All
# (variant, chunk) pairs go into ONE job queue so every slot the box gives us
# stays busy across variants, not one variant at a time.
#
# usage: _enable_drive.sh <TAG> [CHUNK]     env: CONCOLIC_SLOTS, DRIVE_PAR
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:?tag}"; CHUNK="${2:-150}"
LOG="$B/_enable_drive_${TAG}.log"
CD="$B/_chunks/$TAG"
export CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-3}"
say(){ echo "[$(date -Is)] $*" >> "$LOG"; }
mkdir -p "$CD"

JOBS="$CD/jobs.txt"; : > "$JOBS"
TOTSEEDS=0
for F in "$B"/_enableR_*.json; do
  [ -s "$F" ] || continue
  V=$(basename "$F" .json); V=${V#_enableR_}
  NCH=$(python3 - "$F" "$CD" "$CHUNK" "$V" <<'PY'
import json,sys,os
seeds=json.load(open(sys.argv[1])); cd,n,v=sys.argv[2],int(sys.argv[3]),sys.argv[4]
k=0
for i in range(0,len(seeds),n):
    json.dump(seeds[i:i+n], open(os.path.join(cd,f"{v}_c{k:04d}.json"),"w")); k+=1
print(k)
PY
)
  n=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
  TOTSEEDS=$((TOTSEEDS+n))
  say "$V: $n seeds -> $NCH chunks"
  for c in $(seq -f "%04g" 0 $((NCH-1))); do echo "$V $c" >> "$JOBS"; done
done
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "=== ENABLE DRIVE $TAG seeds=$TOTSEEDS jobs=$(wc -l < "$JOBS") chunk=$CHUNK "\
"slots=$CONCOLIC_SLOTS par=${DRIVE_PAR:-$CONCOLIC_SLOTS} corpus_before=$before ==="

cat > "$CD/worker.sh" <<'WS'
#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
V="$1"; C="$2"; TAG="$3"; CD="$B/_chunks/$TAG"
SFX="$( [ "${V##*_}" = typed ] && echo t || echo p )"
[ -f "$CD/done_${V}_${C}" ] && exit 0
TOT=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$CD/${V}_c${C}.json")
POS=0; TRY=0; LOST=0
while [ "$POS" -lt "$TOT" ] && [ "$TRY" -lt 80 ]; do
  REM="$CD/rem_${V}_${C}.json"
  python3 -c "
import json,sys
json.dump(json.load(open(sys.argv[1]))[int(sys.argv[2]):],open(sys.argv[3],'w'))" \
    "$CD/${V}_c${C}.json" "$POS" "$REM"
  OUT="$CD/log_${V}_${C}_${TRY}.log"
  /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
    EXTRA_SEEDS_JSON="$REM" \
    LABEL_SUFFIX="_${TAG}${V:0:3}${SFX}${C}r${TRY}" \
    MAX_RUNS=100000 TIME_BUDGET=3600 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$OUT" 2>&1
  rc=$?
  n=$(grep -c 'new path' "$OUT")
  POS=$((POS+n))
  if [ "$rc" != "0" ]; then
    echo "[$(date -Is)] $V c$C try$TRY rc=$rc paths=$n -> dropping toxic seed #$POS" \
      >> "$B/_enable_drive_${TAG}.log"
    POS=$((POS+1)); LOST=$((LOST+1))
  fi
  rm -f "$OUT"; TRY=$((TRY+1))
  [ "$rc" = "0" ] && break
done
rm -f "$CD/rem_${V}_${C}.json"
echo "[$(date -Is)] $V c$C DONE consumed=$POS/$TOT tries=$TRY toxic=$LOST" \
  >> "$B/_enable_drive_${TAG}.log"
touch "$CD/done_${V}_${C}"
WS
chmod +x "$CD/worker.sh"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 4600 "$(basename "$0")"
awk -v t="$TAG" '{print $1" "$2" "t}' "$JOBS" | xargs -P "${DRIVE_PAR:-$CONCOLIC_SLOTS}" -L1 "$CD/worker.sh"
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "corpus after: $after (+$((after-before)))"
say "=== ENABLE DRIVE $TAG END ==="
