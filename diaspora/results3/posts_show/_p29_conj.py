#!/usr/bin/env python3
"""P29 — §16e's own numbers, computed by hand on the corpus for round 6's
NON-WALKING gaps, so the pass's result is predicted before it is run.

For each gap: P = its leaf-group gate prefix (`gates` in _p26_gaps_P26F.json),
d = the demanded member that did not walk.
    A = profiles matching P            (A = 0 -> REPORTED, never inferred)
    B = profiles matching P that EVALUATE d
§16e forecloses d under P iff A > 0 and B = 0.
"""
import json, os, pickle, collections, re

B = os.path.dirname(os.path.abspath(__file__))
M = pickle.load(open(B + "/_p29_decmatrix.pkl", "rb"))
E = M["exprs"]; ROWS = M["rows"]; EI = {e: i for i, e in enumerate(E)}
per = json.load(open(B + "/_p29_perkey_P26F.json"))
gaps = {g["id"]: g for g in json.load(open(B + "/_p26_gaps_P26F.json"))}

MASKS = [r[0] for r in ROWS]


def matches(m, pfx):
    for g, o in pfx:
        j = EI.get(g)
        if j is None or j not in m:
            return False
        if not (m[j] & (2 if o else 1)):
            return False
    return True


tab = collections.Counter()
detail = collections.defaultdict(collections.Counter)
rows = []
for gid, r in per.items():
    if r["walked"]:
        continue
    g = gaps[gid]
    pfx = [(k, bool(v)) for k, v in (g.get("gates") or {}).items() if k in EI]
    bad = [l for l in r["lits"] if l["v"] != "honoured"]
    d = bad[0]["e"]
    di = EI.get(d)
    sel = [m for m in MASKS if matches(m, pfx)]
    A = len(sel)
    Bc = sum(1 for m in sel if di in m) if di is not None else -1
    if A == 0:
        cls = "A=0  gate conjunction NEVER matched (REPORTED, §16e never infers)"
    elif Bc == 0:
        cls = "A>0 B=0  §16e FORECLOSES the member -> demand retired"
    else:
        cls = "A>0 B>0  member IS evaluated under its own gates -> drivable"
    tab[(bad[0]["v"], bad[0]["fam"], cls)] += 1
    detail[(bad[0]["v"], bad[0]["fam"])][cls] += 1
    rows.append({"gap": gid, "verdict": bad[0]["v"], "fam": bad[0]["fam"],
                 "member": d, "gates": len(pfx), "A": A, "B": Bc, "cls": cls})

print("round-6 NON-WALKING gaps:", len(rows))
print()
print("%-16s %-24s %-58s %5s" % ("verdict", "family", "§16e class", "n"))
for (v, f, c), n in sorted(tab.items(), key=lambda kv: -kv[1]):
    print("%-16s %-24s %-58s %5d" % (v, f, c[:58], n))
print()
print("BY FIRST-BAD CLASS")
for k, c in sorted(detail.items(), key=lambda kv: -sum(kv[1].values())):
    print("  %-16s %-24s  %s" % (k[0], k[1], dict(c)))
json.dump(rows, open(B + "/_p29_conj.json", "w"), indent=1)
print("\nP29-CONJ-DONE")


def why_a0():
    """For every A=0 gap: which gate literal of P drops the match count to 0,
    and is it the literal itself or only its CONJUNCTION with the others?"""
    print("\n=== A=0 ANALYSIS: what makes the gate conjunction unmatched ===")
    blame = collections.Counter(); shape = collections.Counter()
    for gid, r in per.items():
        if r["walked"]:
            continue
        g = gaps[gid]
        pfx = [(k, bool(v)) for k, v in (g.get("gates") or {}).items() if k in EI]
        sel = [m for m in MASKS if matches(m, pfx)]
        if sel:
            continue
        # singly-matched counts
        singles = {}
        for lit in pfx:
            singles[lit] = sum(1 for m in MASKS if matches(m, [lit]))
        zero = [l for l, c in singles.items() if c == 0]
        if zero:
            for l in zero:
                blame[("SINGLE LITERAL never observed", l[0][:80], l[1])] += 1
            shape["single literal never observed"] += 1
            continue
        # greedy: add literals in order, find the first that zeroes it
        cur = []
        for lit in pfx:
            cur.append(lit)
            if not any(matches(m, cur) for m in MASKS):
                blame[("CONJUNCTION dies at", lit[0][:80], lit[1])] += 1
                shape["conjunction of %d gates, all singly observed" % len(pfx)] += 1
                break
    for k, n in shape.most_common():
        print("   %-60s %5d" % (k, n))
    print()
    for k, n in blame.most_common(15):
        print("   %-34s %-82s %-6s %4d" % (k[0], k[1], k[2], n))


why_a0()
