#!/bin/bash
# Three arms of the step-6 parallelisation differential on one batch:
#   A  OLD engine (src/), serial            -- the reference
#   B  NEW engine, COVERAGE_PAR unset       -- the refactor, serial
#   C  NEW engine, COVERAGE_PAR=<width>     -- the refactor, pooled
# The summary JSON of all three must be BYTE-IDENTICAL, and B's/C's per-set
# checkpoint records must be the same SET.
set +e
unset JAVA_TOOL_OPTIONS
B="$1"; WIDTH="${2:-8}"; OUT="$3"
NEW_ENGINE="$4"
TOOLS=/home/dev/project/reports/diaspora/results3/tools
mkdir -p "$OUT"
NAME=$(basename "$B")

run_arm() {
  local tag="$1" engine="$2" par="$3"
  echo "=== ARM $tag  engine=$engine  COVERAGE_PAR=${par:-<unset>} $(date -Is)"
  local t0=$(date +%s)
  env ENGINE_SRC="$engine" \
      ${par:+COVERAGE_PAR=$par} \
      SUMMARY_OUT="$OUT/${NAME}_${tag}.summary.json" \
      COVERAGE_CHECKPOINT="$OUT/${NAME}_${tag}.ckpt.jsonl" \
      python3 -u "$TOOLS/cov_par_differential.py" "$B/coverage_report.py" \
      > "$OUT/${NAME}_${tag}.stdout" 2>&1
  local t1=$(date +%s)
  echo "ARM $tag WALL=$((t1-t0))s rc=$?"
  echo "$((t1-t0))" > "$OUT/${NAME}_${tag}.wall"
}

run_arm A /home/dev/project/src ""
run_arm B "$NEW_ENGINE" ""
run_arm C "$NEW_ENGINE" "$WIDTH"

echo "=== BYTE IDENTITY ==="
for x in B C; do
  if cmp -s "$OUT/${NAME}_A.summary.json" "$OUT/${NAME}_${x}.summary.json"; then
    echo "summary A == $x : IDENTICAL ($(md5sum < "$OUT/${NAME}_A.summary.json" | cut -c1-12))"
  else
    echo "summary A != $x : DIFFERS"
    diff "$OUT/${NAME}_A.summary.json" "$OUT/${NAME}_${x}.summary.json" | head -40
  fi
done
echo "=== CHECKPOINT RECORD SETS ==="
for x in A B C; do
  f="$OUT/${NAME}_${x}.ckpt.jsonl"
  [ -f "$f" ] && echo "$x: $(wc -l < "$f") lines, keys-md5 $(python3 -c "
import json,sys,hashlib
ks=[]
for l in open('$f'):
    l=l.strip()
    if not l: continue
    try: d=json.loads(l)
    except Exception: continue
    if 'k' in d: ks.append(d['k'])
print(hashlib.md5('|'.join(sorted(ks)).encode()).hexdigest()[:12], len(ks))
")"
done
echo "=== WALLS ==="
for x in A B C; do echo "$x: $(cat "$OUT/${NAME}_${x}.wall" 2>/dev/null)s"; done
