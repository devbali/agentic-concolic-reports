#!/usr/bin/env python3
"""C18 — the A = 0 GATE-PREFIX table asked for by the round brief:

    prefix | driven cubes | driven runs | which gate came out contradicted |
    consistency % | was the prefix REALISED | corpus A now

The 32 prefixes are the C16 enumerator's `unmatched` list (`_c16_conj.json`),
i.e. the A = 0 gate conjunctions as they stood BEFORE the C16A drive; the
"still A = 0" column is read from the C17R2 pass checkpoint, after it.
"""
import glob, json, os, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals   # noqa: E402

_UNLEN = re.compile(r"len\(([^()]+)\)")
conj = json.load(open(os.path.join(HERE, "_c16_conj.json")))
prefixes = [tuple((e, bool(o)) for e, o in p) for p, _m in conj["unmatched"]]
gaps = json.load(open(os.path.join(HERE, "_c16_gaps.json")))
bypref = defaultdict(list)
for g in gaps:
    if not g.get("unmatched"):
        continue
    bypref[tuple(sorted((e, bool(o)) for e, o in g["pre"].items()))].append(g["id"])

# still A = 0 after the drive?
still = set()
f = open(os.path.join(HERE, "_cov_c18_C18R1.ckpt.jsonl")
         if os.path.exists(os.path.join(HERE, "_cov_c18_C18R1.ckpt.jsonl"))
         else os.path.join(HERE, "_cov_c16_C17R2.ckpt.jsonl"))
f.readline()
for line in f:
    r = json.loads(line); v = r.get("v") or {}
    for c in (v.get("conj") or []):
        if c[2] == 0:
            still.add(tuple((e, bool(o)) for e, o in c[0]))

want = {i for ids in bypref.values() for i in ids}
runs = defaultdict(list)
for fp in sorted(glob.glob(os.path.join(HERE, "dump_*_C16A*.json"))):
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    gid = (d.get("concolic_seeds") or {}).get("__c13gap__")
    if gid not in want:
        continue
    canonicalize_ordinals(d)
    pcs = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") != "path_condition":
            continue
        ex = e["expr"]; pcs[ex].add(bool(e.get("taken")))
        ex2 = _UNLEN.sub(r"SYM_LEN_\1", ex)
        if ex2 != ex:
            pcs[ex2].add(bool(e.get("taken")))
    runs[gid].append((pcs, (d.get("error") or {}).get("type") or "-"))

print(f"{'#':>3} {'cubes':>5} {'runs':>5}  {'realised':>8} {'stillA0':>7}  "
      f"blocking gate literal (verdict over the driven runs)")
rows = []
for i, pre in enumerate(prefixes):
    key = tuple(sorted(pre))
    ids = bypref.get(key, [])
    rr = [r for gid in ids for r in runs.get(gid, ())]
    per = {}
    for e, o in pre:
        hit = sum(1 for pcs, _ in rr if e in pcs and o in pcs[e])
        opp = sum(1 for pcs, _ in rr if e in pcs and o not in pcs[e])
        nev = sum(1 for pcs, _ in rr if e not in pcs)
        per[(e, o)] = (hit, opp, nev)
    realised = sum(1 for pcs, _ in rr
                   if all(e in pcs and o in pcs[e] for e, o in pre))
    bad = [(e, o, v) for (e, o), v in per.items() if v[0] < len(rr)]
    rows.append({"prefix": [list(x) for x in pre], "cubes": len(ids),
                 "runs": len(rr), "realised": realised,
                 "still_A0": pre in still,
                 "blocking": [{"expr": e, "outcome": o, "honoured": v[0],
                               "contradicted": v[1], "never_evaluated": v[2],
                               "consistency_pct": round(100.0 * (v[1] + v[2]) / max(1, len(rr)), 1)}
                              for e, o, v in bad]})
    tag = ", ".join(f"{'CON' if v[1] else 'NEV'} {e.split('_row_target_')[-1][:44]} "
                    f"{round(100.0*(v[1]+v[2])/max(1,len(rr)))}%" for e, o, v in bad) or "-none-"
    print(f"{i:>3} {len(ids):>5} {len(rr):>5}  {realised:>8} {str(pre in still):>7}  {tag}")
json.dump(rows, open(os.path.join(HERE, "_c18_a0_table.json"), "w"), indent=1)
tot = Counter()
for r in rows:
    tot["prefixes"] += 1
    tot["still_A0"] += r["still_A0"]
    tot["realised_by_a_driven_run"] += bool(r["realised"])
    for b in r["blocking"]:
        tot[f"blocking:{'CON' if b['contradicted'] else 'NEV'}:"
            f"{'mentions_container' if 'mentions_container' in b['expr'] else 'other'}"] += 1
print("\n", dict(tot))
print("C18-A0-TABLE-DONE")
