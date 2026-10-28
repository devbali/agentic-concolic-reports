#!/usr/bin/env python3
"""P28b (read-only) — the DECIDING differential for the ambiguity `_p28_seedkey_probe.py`
found: `len(SYM_RESULT_ActiveRecord__Relation_records_N_rows)` is seeded N>0 and
mints 0 on 2 218 of 3 289 observations.

Two hypotheses, and they make OPPOSITE predictions:

  H-NAME (notifications' C17 defect): the dimension IS under seed control but at
        a DIFFERENT name; the value the seed asked for was minted SOMEWHERE, under
        another variable. Prediction: in the same dump there is another list-length
        variable holding N whose note binds the same owner.
  H-FEAS: the seed WAS consulted at this very name and the value 0 is what the
        program produced anyway -- the base does not walk the enabling gate, so the
        query is empty. Prediction: NO other variable in the dump carries N for
        this owner; the 0 is the answer, not a lost seed.

usage: SAMPLE=400 python3 -u _p28_seedkey_upstream.py
"""
import json, os, random, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_pruned_P26E2.txt"))
N = int(os.environ.get("SAMPLE", "400"))
BIND = re.compile(r"\$\$\(([A-Za-z0-9_]+)\)")
TARGET = "len(SYM_RESULT_ActiveRecord__Relation_records_"

files = [l.strip() for l in open(LIST) if l.strip()]
random.seed(281); files = random.sample(files, min(N, len(files)))

verdict = Counter()
whichvar = Counter()
sql_of_zero = Counter()
examples = []
scanned = 0

for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    scanned += 1
    seeds = d.get("concolic_seeds") or {}
    svs = {}
    for sv in d.get("symbolic_vars") or ():
        n = sv.get("name")
        if n:
            svs[n] = (sv.get("value"), sv.get("note") or "")
    lens = {n: v for n, (v, nt) in svs.items() if n.startswith("len(")}
    for k, sval in seeds.items():
        if not k.startswith(TARGET):
            continue
        if k not in svs:
            continue
        val, note = svs[k]
        try:
            s_i, v_i = int(sval), int(val)
        except Exception:
            continue
        if s_i <= 0 or v_i == s_i:
            verdict["seed honoured (or seed 0)"] += 1
            continue
        # seed N>0 but minted something else -- test the two hypotheses
        owner = k[len(TARGET):].rsplit("_rows)", 1)[0]
        ownkey = owner.split("_")[0]
        carriers = [n2 for n2, v2 in lens.items()
                    if n2 != k and v2 == s_i
                    and (ownkey and ownkey in n2)]
        if carriers:
            verdict[f"H-NAME: value {s_i} found on ANOTHER var for this owner"] += 1
            whichvar[re.sub(r"_\d+_", "_N_", carriers[0])] += 1
            if len(examples) < 5:
                examples.append((os.path.basename(fp), k, s_i, v_i, carriers[:2]))
        else:
            verdict[f"H-FEAS: value {s_i} appears NOWHERE for this owner (minted {v_i})"] += 1
            sql_of_zero[(note[:70] or "<no note>")] += 1
            if len(examples) < 5:
                examples.append((os.path.basename(fp), k, s_i, v_i, None))

print(f"scanned {scanned} dumps, target family {TARGET}...\n")
for k, v in verdict.most_common():
    print(f"  {v:8d}  {k}")
print("\nif H-NAME ever fired, the variables that carried the value:")
for k, v in whichvar.most_common(8):
    print(f"  {v:8d}  {k[:100]}")
print("\nnotes on the mints that produced a value != seed (H-FEAS bucket):")
for k, v in sql_of_zero.most_common(8):
    print(f"  {v:8d}  {k}")
print("\nexamples:")
for e in examples:
    print(f"  {e[0]}\n     {e[1]}\n     seed {e[2]} -> minted {e[3]}   carriers={e[4]}")
print("P28-UPSTREAM-DONE")
