#!/usr/bin/env python3
"""C18 — for each OPEN leaf, the MINIMAL subset of its own literals under
which the never-evaluated member is foreclosed (A > 0, B = 0).

If that subset is the leaf's GATE prefix, §16e should already have removed
the member and something is wrong; if it is not, the foreclosure conditions
on NON-GATE members and §16e (gate-conjunction only) cannot reach it. This
tells the two apart, per leaf, on the corpus itself.
"""
import itertools, json, os, pickle, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
idx = pickle.load(open(os.path.join(HERE, "_c16_index.pkl"), "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}; dumps = idx["dumps"]
N = len(dumps); NB = (N + 7) // 8
TB = [bytearray(NB) for _ in exprs]; FB = [bytearray(NB) for _ in exprs]
EB = [bytearray(NB) for _ in exprs]
for i, (_p, _v, em, tm, _ns, _cm) in enumerate(dumps):
    by, b = i >> 3, 1 << (i & 7)
    m = em
    while m:
        bb = m & -m; j = bb.bit_length() - 1; m ^= bb
        EB[j][by] |= b
        (TB if (tm >> j) & 1 else FB)[j][by] |= b
ti = lambda x: int.from_bytes(bytes(x), "little")
TB = [ti(x) for x in TB]; FB = [ti(x) for x in FB]; EB = [ti(x) for x in EB]
ALL = (1 << N) - 1

res = json.load(open(os.path.join(HERE, "_c16_residue.json")))["leaves"]
gaps = {g["id"]: g for g in json.load(open(os.path.join(HERE, "_c16_gaps.json")))}
open_leaves = [x for x in res if not x["A0_at_gate_conjunction"] and x["rule_T_members"] == 0]
print(f"open leaves {len(open_leaves)}; corpus {N} dumps")

out = []
summary = Counter()
for x in open_leaves:
    gid = x["batch_ids"][0]
    gate = set((e, bool(o)) for e, o in gaps[gid]["pre"].items()) if gid in gaps else set()
    tgt = [k for k in x["keys"] if k["evaluated_under_others"] == 0]
    for k in tgt:
        others = [(kk["expr"], kk["outcome"]) for kk in x["keys"] if kk["expr"] != k["expr"]]
        j = eidx.get(k["expr"])
        if j is None:
            continue
        best = None
        for r in range(1, 4):
            for sub in itertools.combinations(others, r):
                m = ALL
                for e2, o2 in sub:
                    j2 = eidx.get(e2)
                    if j2 is None:
                        continue
                    m &= TB[j2] if o2 else FB[j2]
                a = m.bit_count()
                if a and not (m & EB[j]).bit_count():
                    best = (sub, a)
                    break
            if best:
                break
        if best:
            sub, a = best
            allgate = all(s in gate for s in sub)
            summary[("minimal size " + str(len(sub)),
                     "ALL-GATE" if allgate else "has NON-GATE member")] += 1
            out.append({"set": x["set"], "member": k["expr"], "outcome": k["outcome"],
                        "minimal_conditioning": [list(s) for s in sub], "A": a,
                        "all_gate": allgate})
        else:
            summary[("no subset of size <= 3 forecloses it", "")] += 1
            out.append({"set": x["set"], "member": k["expr"], "outcome": k["outcome"],
                        "minimal_conditioning": None, "A": None, "all_gate": None})
for k, v in summary.most_common():
    print(f"  {v:4d}  {k}")
seen = set()
for o in out:
    if o["minimal_conditioning"] is None:
        continue
    key = (o["member"], tuple(map(tuple, o["minimal_conditioning"])))
    if key in seen:
        continue
    seen.add(key)
    print(f"\n  member  {o['outcome']}  {o['member']}")
    print(f"  A={o['A']}  all-gate={o['all_gate']}")
    for e, ov in o["minimal_conditioning"]:
        print(f"     cond {ov}  {e}")
json.dump(out, open(os.path.join(HERE, "_c18_minimal_cond.json"), "w"), indent=1)
print("\nC18-MINIMAL-COND-DONE")
