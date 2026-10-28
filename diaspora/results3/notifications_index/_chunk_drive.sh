#!/bin/bash
# CHUNKED BULK DRIVE (2026-09-10) — the v3.1 drive lost six of seven variants.
#
# WHY. `_diverse_drive.sh` hands ALL 8 000 seeds to ONE JRuby per variant. On
# DV31a100610 every non-xml variant died at path #277 — `munmap_chunk():
# invalid pointer` / SIGSEGV in `libcurl.so.4` — so html/json/mobile got 277
# runs each while xml_plain got 8 000. DV3a100600 died the same way at #119.
# A native abort in the JVM is unrecoverable and takes the WHOLE seed list
# with it, so a bulk drive silently delivers 3 % of its budget.
#
# THE FIX. Split the seed list into CHUNKS and give each chunk its own JRuby.
# An abort then costs at most one chunk, the next chunk starts on a fresh VM,
# and the drive names the chunk it lost instead of stopping. Every chunk gets
# its own LABEL_SUFFIX (TAG + variant + chunk index) so dump labels stay
# unique per invocation, as the standing correction requires.
#
# usage: _chunk_drive.sh <seeds.json> <TAG> [CHUNK] [variant ...]
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
SEEDS="$1"; TAG="$2"; CHUNK="${3:-200}"; shift 3 2>/dev/null
VARS="${*:-html_plain html_typed json_plain json_typed mobile_plain mobile_typed xml_plain}"
LOG="$B/_chunk_drive_${TAG}.log"
CD="$B/_chunks/$TAG"
export CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-3}"
say(){ echo "[$(date -Is)] $*" >> "$LOG"; }

mkdir -p "$CD"
NCH=$(python3 - "$SEEDS" "$CD" "$CHUNK" <<'PY'
import json,sys,os
seeds=json.load(open(sys.argv[1])); cd=sys.argv[2]; n=int(sys.argv[3])
k=0
for i in range(0,len(seeds),n):
    json.dump(seeds[i:i+n], open(os.path.join(cd,f"c{k:04d}.json"),"w")); k+=1
print(k)
PY
)
say "=== CHUNK DRIVE $TAG seeds=$SEEDS chunk=$CHUNK chunks=$NCH variants='$VARS' slots=$CONCOLIC_SLOTS ==="
before=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l); say "corpus before: $before dumps"

# job queue: one line per (variant, chunk); 3 workers pull from it via xargs.
JOBS="$CD/jobs.txt"; : > "$JOBS"
for V in $VARS; do
  for c in $(seq -f "%04g" 0 $((NCH-1))); do echo "$V $c" >> "$JOBS"; done
done
say "$(wc -l < "$JOBS") jobs queued"

cat > "$CD/worker.sh" <<'WS'
#!/bin/bash
# One chunk, RESUMED ACROSS ABORTS. The native abort is SEED-DETERMINISTIC
# (measured 2026-09-10: the full DV31a100610 drive and an independent 200-seed
# chunk both died on absolute seed #277), so after an abort the worker drops
# exactly the seed that killed the VM, restarts on the remainder, and keeps
# going. Yield is then ~100 % of the chunk minus the handful of toxic seeds,
# instead of "everything after the first abort".
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/notifications_index
V="$1"; C="$2"; TAG="$3"; CD="$B/_chunks/$TAG"
SFX="$( [ "${V##*_}" = typed ] && echo t || echo p )"
[ -f "$CD/done_${V}_${C}" ] && exit 0
TOT=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$CD/c${C}.json")
POS=0; TRY=0; LOST=0
while [ "$POS" -lt "$TOT" ] && [ "$TRY" -lt 80 ]; do
  REM="$CD/rem_${V}_${C}.json"
  python3 -c "
import json,sys
s=json.load(open(sys.argv[1]))[int(sys.argv[2]):]
json.dump(s,open(sys.argv[3],'w'))" "$CD/c${C}.json" "$POS" "$REM"
  OUT="$CD/log_${V}_${C}_${TRY}.log"
. /home/dev/project/reports/diaspora/results3/notifications_index/_wait_mem.sh
wait_mem 4096 "$(basename "$0")"
  systemd-run --user --slice=concolic-cov.slice --scope \
    -p MemoryMax="${JRUBY_CAP:-2G}" -p MemorySwapMax=0 --quiet choom -n 1000 -- \
    /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
    EXTRA_SEEDS_JSON="$REM" \
    LABEL_SUFFIX="_${TAG}${V:0:3}${SFX}${C}r${TRY}" \
    MAX_RUNS=100000 TIME_BUDGET=3600 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$OUT" 2>&1
  rc=$?
  n=$(grep -c 'new path' "$OUT")
  POS=$((POS+n))
  if [ "$rc" != "0" ]; then
    echo "[$(date -Is)] $V c$C try$TRY rc=$rc paths=$n -> dropping toxic seed #$POS" >> "$B/_chunk_drive_${TAG}.log"
    POS=$((POS+1)); LOST=$((LOST+1))
  fi
  rm -f "$OUT"
  TRY=$((TRY+1))
  [ "$rc" = "0" ] && break
done
rm -f "$CD/rem_${V}_${C}.json"
echo "[$(date -Is)] $V c$C DONE consumed=$POS/$TOT tries=$TRY toxic=$LOST" >> "$B/_chunk_drive_${TAG}.log"
touch "$CD/done_${V}_${C}"
WS
chmod +x "$CD/worker.sh"

# DRIVE_PAR: how many workers THIS drive runs. CONCOLIC_SLOTS is how many
# machine-wide JRuby locks exist (tools/slot). They are different numbers when
# another agent is driving another endpoint on the same box: keep the lock
# count at 3 so a free slot is usable, but launch fewer workers so the other
# drive is not starved. Default: CONCOLIC_SLOTS (previous behaviour).
awk -v t="$TAG" '{print $1" "$2" "t}' "$JOBS" | xargs -P "${DRIVE_PAR:-$CONCOLIC_SLOTS}" -L1 "$CD/worker.sh"

after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "corpus after: $after dumps (+$((after-before)))"
say "crashed chunks: $(grep -c 'crash=[1-9]' "$LOG")"
say "=== CHUNK DRIVE $TAG END ==="
