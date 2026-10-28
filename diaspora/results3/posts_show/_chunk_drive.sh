#!/bin/bash
# CHUNKED BULK DRIVE for posts_show — port of notifications_index's
# `_chunk_drive.sh` (2026-09-10), which exists because a bulk drive that hands
# ALL seeds to ONE JRuby per variant loses everything after the first native
# abort: a libcurl/JFFI SIGSEGV is unrecoverable and takes the whole seed list.
#
# Split the seed list into CHUNKS, one JRuby per chunk. An abort then costs at
# most one chunk, the next chunk starts on a fresh VM, and the drive NAMES the
# chunk it lost instead of stopping. Every chunk gets its own LABEL_SUFFIX
# (TAG + variant + chunk index) so dump labels stay unique per invocation.
#
# posts_show differences from the notifications port, both forced by this
# runner: VARIANTS are `auth_html anon_html auth_json anon_json` (added to
# run_dse.rb during this drive, §8), and progress is measured by COUNTING THE
# DUMPS the invocation actually wrote — this runner prints a `paths=` line only
# every 25 paths, so `grep -c 'new path'` (notifications' resume signal) would
# undercount by up to 25 and silently re-run seeds.
#
# usage: _chunk_drive.sh <seeds.json> <TAG> [CHUNK] [variant ...]
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
SEEDS="$1"; TAG="$2"; CHUNK="${3:-200}"; shift 3 2>/dev/null
VARS="${*:-auth_html anon_html auth_json anon_json}"
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

JOBS="$CD/jobs.txt"; : > "$JOBS"
for V in $VARS; do
  for c in $(seq -f "%04g" 0 $((NCH-1))); do echo "$V $c $TAG" >> "$JOBS"; done
done
say "$(wc -l < "$JOBS") jobs queued"

cat > "$CD/worker.sh" <<'WS'
#!/bin/bash
# One chunk, RESUMED ACROSS ABORTS. A native abort is seed-deterministic
# (notifications, measured 2026-09-10), so after an abort the worker drops
# exactly the seed that killed the VM, restarts on the remainder, and keeps
# going. Yield is then ~100% of the chunk minus the handful of toxic seeds.
set +e; unset JAVA_TOOL_OPTIONS
# Explicit per-JVM heap cap (2026-09-17, three OOM failures on the CLASSBV1
# drive: 20G/w16, 40G/w12, and even 50G/w8 died in <2 min wall time -- too
# fast to be a slow leak, consistent with JVM container-aware ergonomics
# sizing each JRuby's default max heap off the WHOLE cgroup's MemoryMax
# rather than a fair per-worker share, so aggregate demand at boot alone can
# exceed the cap however high it's set. JAVA_OPTS -Xmx is honoured directly
# by the jruby launcher (confirmed by reading bin/jruby) and overrides that
# ergonomic default. DRIVE_XMX is overridable by the caller; default sized
# for a MemoryMax/DRIVE_PAR budget with slack for native/metaspace/off-heap.
export JAVA_OPTS="-Xmx${DRIVE_XMX:-1536m} -XX:MaxMetaspaceSize=${DRIVE_MAXMETA:-768m} $JAVA_OPTS"
# 2026-09-17 attempt 4 (v4): -Xmx1536m held (ps confirmed heap RSS ~0.25-0.3GB
# per worker for the first 2.7 min) yet the WHOLE CGROUP still OOM'd ~5 min in
# with zero dumps produced -- so the heap was never the leak. -Xmx does NOT
# bound JVM Metaspace (class metadata) or JIT-generated native code, and
# JRuby specifically compiles every executed Ruby method into a JVM bytecode
# class stored in Metaspace, which is UNBOUNDED by default and can dwarf the
# heap on a big Rails app (diaspora) exercised across many distinct code
# paths, especially x12 concurrent full app boots. Two independent mitigations
# stacked here: (1) an explicit MaxMetaspaceSize cap as a hard backstop, and
# (2) --dev mode (below, via JRUBY_OPTS) which disables JRuby's JIT compiler
# entirely (interpreted-only), which is the mechanism that generates those
# classes in the first place -- this should be the dominant fix; the
# metaspace cap is only a safety net in case interpreted mode still compiles
# something.
export JRUBY_OPTS="--dev ${JRUBY_OPTS:-}"
B=/home/dev/project/reports/diaspora/results3/posts_show
V="$1"; C="$2"; TAG="$3"; CD="$B/_chunks/$TAG"
[ -f "$CD/done_${V}_${C}" ] && exit 0
TOT=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$CD/c${C}.json")
POS=0; TRY=0; LOST=0
while [ "$POS" -lt "$TOT" ] && [ "$TRY" -lt 80 ]; do
  REM="$CD/rem_${V}_${C}.json"
  python3 -c "
import json,sys
s=json.load(open(sys.argv[1]))[int(sys.argv[2]):]
json.dump(s,open(sys.argv[3],'w'))" "$CD/c${C}.json" "$POS" "$REM"
  SFX="_${TAG}${V:0:2}${V:5:2}${C}r${TRY}"
  OUT="$CD/log_${V}_${C}_${TRY}.log"
  /home/dev/project/reports/diaspora/tools/slot env VARIANTS="$V" SEEDS_ONLY=1 \
    EXTRA_SEEDS_JSON="$REM" LABEL_SUFFIX="$SFX" \
    MAX_RUNS=100000 TIME_BUDGET=3600 \
    /home/dev/project/scripts/diaspora-concolic "$B/run_dse.rb" > "$OUT" 2>&1
  rc=$?
  # COUNT THE ARTEFACT, not a log line (DISCIPLINE §12): this runner prints a
  # progress line only every 25 paths.
  n=$(find "$B" -maxdepth 1 -name "dump_*${SFX}.json" | wc -l)
  POS=$((POS+n))
  if [ "$rc" != "0" ]; then
    echo "[$(date -Is)] $V c$C try$TRY rc=$rc dumps=$n -> dropping toxic seed #$POS" >> "$B/_chunk_drive_${TAG}.log"
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
# machine-wide JRuby locks exist (tools/slot). They differ when another agent
# is driving another endpoint on the same box: keep the lock count at 3 so a
# free slot is usable, but launch fewer workers so the other drive is not
# starved.
xargs -P "${DRIVE_PAR:-2}" -L1 "$CD/worker.sh" < "$JOBS"

after=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
say "corpus after: $after dumps (+$((after-before)))"
say "toxic seeds dropped: $(grep -c 'dropping toxic seed' "$LOG")"
say "=== CHUNK DRIVE $TAG END ==="
