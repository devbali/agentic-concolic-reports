#!/usr/bin/env python3
"""P30 — the round-7 gap list, FILTERED to what §16f still demands.

A gap is DROPPED when the pass's own §16f inference forecloses the member the
run did not walk under a conjunction `C` the gap's OWN cube already fixes:
`(C, d)` is in `subconjunction_foreclosure_list`, `d` is the gap's first-bad
member, and every literal of `C` is a literal of the gap's cube. That is the
same claim the engine applied — it is READ OFF the pass, never re-derived.

  usage: SUMMARY=<_cov_FINAL_*.json> [EXPLAIN=..] [GAPS=..] [OUT=..]
         python3 _p30_gapfilter.py
"""
import json, os, re, sys, collections

B = os.path.dirname(os.path.abspath(__file__))
SUM = os.environ.get("SUMMARY", B + "/_cov_FINAL_P30A_20260913.json")
EXPL = os.environ.get("EXPLAIN", B + "/_p29_explain_P29A.json")
GAPS = os.environ.get("GAPS", B + "/_p26_gaps_P26F.json")
OUT = os.environ.get("OUT", B + "/_p30_gaps_live.json")


def lits(nc):
    out, depth, cur = [], 0, []
    i, n = 0, len(nc or "")
    while i < n:
        c = nc[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if depth == 0 and nc.startswith(" AND ", i):
            out.append("".join(cur)); cur = []; i += 5; continue
        cur.append(c); i += 1
    if cur:
        out.append("".join(cur))
    res = []
    for t in out:
        t = t.strip()
        if not t:
            continue
        pol = True
        while t.startswith("Not(") and t.endswith(")"):
            t = t[4:-1].strip(); pol = not pol
        res.append((t, pol))
    return res


s = json.load(open(SUM))
rows = s.get("subconjunction_foreclosure_list") or []
by_member = collections.defaultdict(list)
for it in rows:
    C = tuple((g, o == "taken") for g, o in it["conditioning"])
    by_member[it["member"]].append((C, it.get("A")))
print(f"§16f classes in the pass: {len(rows)} over {len(by_member)} distinct members")

ex = json.load(open(EXPL))["per_gap"]
gaps = json.load(open(GAPS))
gapx = {g["id"]: g for g in gaps}
keep, dropped = [], []
stat = collections.Counter()
for gid, r in ex.items():
    if r["walked"]:
        stat["walked in round 7"] += 1
        continue
    g = gapx.get(gid)
    if g is None:
        stat["gap not in list"] += 1
        continue
    L = dict(lits(g["node_constraint"]))
    fb = r["first_bad"]
    member = next((e for e in L if e.startswith(fb[:60])), fb)
    hit = None
    for C, A in by_member.get(member, ()):
        if all(L.get(e) == o for e, o in C):
            hit = (C, A); break
    if hit is not None:
        dropped.append({"gap": gid, "member": member,
                        "C": [[e, o] for e, o in hit[0]], "A": hit[1]})
        stat["FORECLOSED by §16f (no longer demanded)"] += 1
    else:
        keep.append(g)
        stat["still demanded"] += 1

json.dump(keep, open(OUT, "w"))
json.dump(dropped, open(OUT.replace(".json", "_dropped.json"), "w"), indent=1)
print(f"round-7 gaps {len(ex)} -> still demanded {len(keep)}, foreclosed {len(dropped)}")
for k, n in stat.most_common():
    print(f"   {k:<48} {n:5d}")
byC = collections.Counter(len(d["C"]) for d in dropped)
print("   dropped by |C|:", dict(sorted(byC.items())))
byM = collections.Counter(d["member"][:70] for d in dropped)
for m, n in byM.most_common(10):
    print(f"     {n:5d}  {m}")
print("P30-GAPFILTER-DONE")
