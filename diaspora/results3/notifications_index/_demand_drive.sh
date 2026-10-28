#!/bin/bash
# Drive the per-variant DEMAND roots (_demandR_<variant>.json) with the
# abort-resume worker of _chunk_drive.sh. usage: _demand_drive.sh <TAG>
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
TAG="${1:?tag}"
LOG="$B/_demand_drive_${TAG}.log"
export CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-3}"
echo "[$(date -Is)] === DEMAND DRIVE $TAG ===" >> "$LOG"
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
echo "[$(date -Is)] corpus before: $before" >> "$LOG"

cat > "$B/_tw/dworker_${TAG}.sh" <<'WS'
#!/bin/bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
F="$1"; TAG="$2"
V=$(basename "$F" .json); V=${V#_demandR_}
SFX="$( [ "${V##*_}" = typed ] && echo t || echo p )"
TOT=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$F")
POS=0; TRY=0; LOST=0
while [ "$POS" -lt "$TOT" ] && [ "$TRY" -lt 80 ]; do
  REM="$B/_tw/drem_${TAG}_${V}.json"
  python3 -c "
import json,sys
json.dump(json.load(open(sys.argv[1]))[int(sys.argv[2]):],open(sys.argv[3],'w'))" "$F" "$POS" "$REM"
  OUT="$B/_tw/dout_${TAG}_${V}_${TRY}.log"
  /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
    EXTRA_SEEDS_JSON="$REM" LABEL_SUFFIX="_${TAG}${V:0:3}${SFX}r${TRY}" \
    MAX_RUNS=100000 TIME_BUDGET=3600 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$OUT" 2>&1
  rc=$?; n=$(grep -c 'new path' "$OUT"); POS=$((POS+n))
  if [ "$rc" != "0" ]; then POS=$((POS+1)); LOST=$((LOST+1)); fi
  rm -f "$OUT"; TRY=$((TRY+1)); [ "$rc" = "0" ] && break
done
rm -f "$REM"
echo "[$(date -Is)] $V consumed=$POS/$TOT tries=$TRY aborted=$LOST" >> "$B/_demand_drive_${TAG}.log"
WS
chmod +x "$B/_tw/dworker_${TAG}.sh"
ls "$B"/_demandR_*.json 2>/dev/null | xargs -r -P "$CONCOLIC_SLOTS" -I{} "$B/_tw/dworker_${TAG}.sh" {} "$TAG"
after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
echo "[$(date -Is)] corpus after: $after (+$((after-before)))" >> "$LOG"
echo "[$(date -Is)] === DEMAND DRIVE $TAG END ===" >> "$LOG"
