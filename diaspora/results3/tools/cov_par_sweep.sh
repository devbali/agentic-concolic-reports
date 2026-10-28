#!/bin/bash
# Step-6 speedup at several widths, on ONE corpus, all arms against the PATCHED
# engine. Every arm writes to its own scratch SUMMARY_OUT and its own scratch
# checkpoint, so no arm can replay another's work; the summaries must all be
# byte-identical to the serial arm's.
set +e
unset JAVA_TOOL_OPTIONS
B="$1"; OUT="$2"; NEW_ENGINE="$3"; shift 3
WIDTHS="$*"
TOOLS=/home/dev/project/reports/diaspora/results3/tools
NAME=$(basename "$B")
mkdir -p "$OUT"

for w in $WIDTHS; do
  tag="w$w"
  echo "=== WIDTH $w  $(date -Is)"
  t0=$(date +%s)
  env ENGINE_SRC="$NEW_ENGINE" COVERAGE_PAR="$w" \
      SUMMARY_OUT="$OUT/${NAME}_sw_${tag}.summary.json" \
      COVERAGE_CHECKPOINT="$OUT/${NAME}_sw_${tag}.ckpt.jsonl" \
      python3 -u "$TOOLS/cov_par_differential.py" "$B/coverage_report.py" \
      > "$OUT/${NAME}_sw_${tag}.stdout" 2>&1
  t1=$(date +%s)
  cov=$(grep -o 'COVERAGE_PHASE_SECONDS=[0-9.]*' "$OUT/${NAME}_sw_${tag}.stdout" | tail -1 | cut -d= -f2)
  echo "  width=$w total=$((t1-t0))s coverage_phase=${cov}s"
done

echo ""
echo "=== SUMMARY: width | coverage-phase s | speedup vs width 1 | summary md5 ==="
base=""
for w in $WIDTHS; do
  tag="w$w"
  cov=$(grep -o 'COVERAGE_PHASE_SECONDS=[0-9.]*' "$OUT/${NAME}_sw_${tag}.stdout" | tail -1 | cut -d= -f2)
  md5=$(md5sum < "$OUT/${NAME}_sw_${tag}.summary.json" 2>/dev/null | cut -c1-12)
  [ -z "$base" ] && base="$cov"
  sp=$(python3 -c "print(f'{$base/max($cov,0.001):.2f}x')" 2>/dev/null)
  echo "  $w | $cov | $sp | $md5"
done

echo ""
echo "=== BYTE IDENTITY vs the serial arm ==="
first=$(echo $WIDTHS | cut -d' ' -f1)
ref="$OUT/${NAME}_sw_w${first}.summary.json"
for w in $WIDTHS; do
  f="$OUT/${NAME}_sw_w${w}.summary.json"
  cmp -s "$ref" "$f" && echo "  width $w: IDENTICAL" || { echo "  width $w: DIFFERS"; diff "$ref" "$f" | head -20; }
done
