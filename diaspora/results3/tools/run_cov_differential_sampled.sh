#!/bin/bash
# MANDATORY differential: the three arms on a corpus that is DELIBERATELY
# INCOMPLETE, so step 6's witness path actually runs.
#
# WHY THIS EXISTS. Both closed endpoints report 0 missing branches, so a
# differential over them never drives the combo loop, the model read-back, or
# the cross-set `reported` dedup -- and `reported` is exactly the shared state
# the parallelisation moved out of the worker and into the parent. A green
# result from a run that could not have gone red is not evidence about that
# path. A random sample of the same corpus is incomplete by construction, so
# every one of those mechanisms runs.
#
# WHAT IT ASSERTS, in increasing strength:
#   1. the summary JSON is byte-identical across arms (covers the first 200
#      witnesses' concrete_values verbatim -- the report caps that list);
#   2. EVERY set's checkpoint record matches, INCLUDING `models`, which is the
#      witness model for every set and is not subject to the 200 cap. Model
#      choice is what is most at risk under a pool, which is why §16d gives
#      each query its own private z3.Context;
#   3. the on-disk record ORDER matches, i.e. the fold really ran in canonical
#      set order and not completion order.
# It also PRINTS the contention the sample actually produced -- sets with
# witnesses, total witnesses, and cross-set repeat cubes -- so a run that
# exercised nothing is visible as such instead of passing quietly.
set +e
unset JAVA_TOOL_OPTIONS
B="$1"; SAMPLE="$2"; WIDTH="${3:-8}"; OUT="$4"; NEW_ENGINE="$5"
TOOLS=/home/dev/project/reports/diaspora/results3/tools
NAME=$(basename "$B")
mkdir -p "$OUT"
P="$OUT/${NAME}_s${SAMPLE}"

run_arm() {
  local tag="$1" engine="$2" par="$3"
  echo "=== ARM $tag  engine=$engine  COVERAGE_PAR=${par:-<unset>}  DUMP_SAMPLE=$SAMPLE"
  local t0=$(date +%s)
  env ENGINE_SRC="$engine" ${par:+COVERAGE_PAR=$par} \
      DUMP_SAMPLE="$SAMPLE" DUMP_SAMPLE_SEED=20260914 \
      SUMMARY_OUT="${P}_${tag}.summary.json" \
      COVERAGE_CHECKPOINT="${P}_${tag}.ckpt.jsonl" \
      python3 -u "$TOOLS/cov_par_differential.py" "$B/coverage_report.py" \
      > "${P}_${tag}.stdout" 2>&1
  local t1=$(date +%s)
  echo "ARM $tag WALL=$((t1-t0))s coverage_phase=$(grep -o 'COVERAGE_PHASE_SECONDS=[0-9.]*' "${P}_${tag}.stdout" | tail -1 | cut -d= -f2)s"
}

run_arm A /home/dev/project/src ""
run_arm B "$NEW_ENGINE" ""
run_arm C "$NEW_ENGINE" "$WIDTH"

python3 - "$P" <<'PYEOF'
import json, sys, collections
P = sys.argv[1]
ARMS = ("A", "B", "C")


def summary(t):
    return open(f"{P}_{t}.summary.json", "rb").read()


def records(t):
    recs, order = {}, []
    for line in open(f"{P}_{t}.ckpt.jsonl"):
        d = json.loads(line)
        if "k" not in d:
            continue
        v = dict(d["v"])
        v.pop("elapsed_ms", None)          # wall time only; never a verdict
        recs[d["k"]] = v
        order.append(d["k"])
    return recs, order


print("\n=== WHAT THIS SAMPLE ACTUALLY EXERCISED ===")
s = json.loads(summary("A"))
rA, oA = records("A")
sets_with = sum(1 for v in rA.values() if v.get("combos"))
witnesses = sum(len(v.get("combos") or []) for v in rA.values())
models = sum(1 for v in rA.values() for m in (v.get("models") or []) if m)
cubes = collections.Counter()
for v in rA.values():
    for c in v.get("combos") or []:
        cubes[json.dumps(sorted(map(list, c)))] += 1
repeats = sum(n - 1 for n in cubes.values() if n > 1)
print(f"  demand_sets={s.get('demand_sets')} missing_branches={s.get('missing_branches')} "
      f"complete={s.get('coverage_complete')}")
print(f"  sets reporting witnesses : {sets_with}")
print(f"  witnesses (cubes) total  : {witnesses}")
print(f"  witnesses carrying a model: {models}")
print(f"  cross-set REPEAT cubes   : {repeats}  <- what `reported` had to dedup")
verdict_ok = True
if sets_with < 2:
    print("  *** WEAK: fewer than 2 sets reported a witness. The cross-set "
          "dedup had no contention; this run is not adequate evidence. ***")
    verdict_ok = False
if witnesses == 0:
    print("  *** VACUOUS: no witness emitted at all -- the path under test "
          "never ran. ***")
    verdict_ok = False

print("\n=== 1. SUMMARY JSON, BYTE-IDENTICAL ===")
a = summary("A")
for t in ("B", "C"):
    same = a == summary(t)
    print(f"  A == {t}: {'IDENTICAL' if same else '*** DIFFERS ***'}")
    verdict_ok &= same

print("\n=== 2. EVERY SET'S RECORD, INCLUDING WITNESS MODELS ===")
for t in ("B", "C"):
    rT, _ = records(t)
    same_keys = set(rA) == set(rT)
    print(f"  A vs {t}: same set keys: {same_keys} ({len(rA)} vs {len(rT)})")
    verdict_ok &= same_keys
    bad_combo = bad_model = 0
    for k in rA:
        if rA[k].get("combos") != rT.get(k, {}).get("combos"):
            bad_combo += 1
        if rA[k].get("models") != rT.get(k, {}).get("models"):
            bad_model += 1
            if bad_model <= 3:
                print(f"    MODEL DIFF at {k}:")
                print(f"      A: {json.dumps(rA[k].get('models'))[:300]}")
                print(f"      {t}: {json.dumps(rT.get(k, {}).get('models'))[:300]}")
    print(f"    sets whose COMBOS differ : {bad_combo}")
    print(f"    sets whose MODELS differ : {bad_model}   <- the model-choice risk")
    verdict_ok &= (bad_combo == 0 and bad_model == 0)
    rest = sum(1 for k in rA if {x: y for x, y in rA[k].items() if x not in ("combos", "models")}
               != {x: y for x, y in rT.get(k, {}).items() if x not in ("combos", "models")})
    print(f"    sets differing elsewhere : {rest}")
    verdict_ok &= (rest == 0)

print("\n=== 3. FOLD ORDER (canonical, not completion) ===")
for t in ("B", "C"):
    _, oT = records(t)
    same = oA == oT
    print(f"  on-disk record order A == {t}: {'IDENTICAL' if same else '*** DIFFERS ***'}")
    verdict_ok &= same

print("\n=== VERDICT ===")
print("  PASS - the witness path ran and every arm agrees" if verdict_ok
      else "  FAIL - see above")
sys.exit(0 if verdict_ok else 1)
PYEOF
