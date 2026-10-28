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
