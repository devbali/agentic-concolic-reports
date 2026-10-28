#!/bin/bash
# Find a DUMP_SAMPLE size whose corpus is incomplete enough to give the
# sampled differential real work: several demand sets reporting witnesses, and
# ideally cross-set repeat cubes so the `reported` dedup has contention.
# Arm A (the reference engine) only -- this is sizing, not proof.
set +e
unset JAVA_TOOL_OPTIONS
B="$1"; OUT="$2"; shift 2
TOOLS=/home/dev/project/reports/diaspora/results3/tools
NAME=$(basename "$B")
mkdir -p "$OUT"

for n in "$@"; do
  env ENGINE_SRC=/home/dev/project/src \
      DUMP_SAMPLE="$n" DUMP_SAMPLE_SEED=20260914 \
      SUMMARY_OUT="$OUT/probe_${NAME}_$n.summary.json" \
      COVERAGE_CHECKPOINT="$OUT/probe_${NAME}_$n.ckpt.jsonl" \
      python3 -u "$TOOLS/cov_par_differential.py" "$B/coverage_report.py" \
      > "$OUT/probe_${NAME}_$n.stdout" 2>&1
  python3 - "$OUT/probe_${NAME}_$n.summary.json" "$OUT/probe_${NAME}_$n.ckpt.jsonl" "$n" <<'EOF'
import json, sys, collections
try:
    s = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"  sample={sys.argv[3]}: NO SUMMARY ({e})"); raise SystemExit
sets_with = 0; total_w = 0; cubes = collections.Counter()
try:
    for l in open(sys.argv[2]):
        d = json.loads(l)
        if 'k' not in d: continue
        cs = d['v'].get('combos') or []
        if cs: sets_with += 1
        total_w += len(cs)
        for c in cs: cubes[json.dumps(sorted(map(list, c)))] += 1
except Exception:
    pass
repeats = sum(v - 1 for v in cubes.values() if v > 1)
print(f"  sample={sys.argv[3]:>6}  demand_sets={s.get('demand_sets')}  "
      f"missing_branches={s.get('missing_branches')}  complete={s.get('coverage_complete')}  "
      f"sets_with_witnesses={sets_with}  witnesses={total_w}  "
      f"cross_set_repeat_cubes={repeats}  <- dedup contention")
EOF
done
