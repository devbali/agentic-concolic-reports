#!/usr/bin/env python3
"""P29 — why round 7's gaps still do not walk, now that CONTRADICTED is 0.

The hypothesis the numbers suggest: the cube demands a list be EMPTY *and* a
decision that only exists when that list is NON-EMPTY. With the construction
now exact on the length gates, that shows up as `never_evaluated` on the row
decision. This measures it against the corpus, per gap.
"""
import json, os, re, sys, pickle, collections

B = os.path.dirname(os.path.abspath(__file__))
M = pickle.load(open(B + "/_p29_decmatrix.pkl", "rb"))
E = M["exprs"]; ROWS = M["rows"]; EI = {e: i for i, e in enumerate(E)}
MASKS = [r[0] for r in ROWS]
gaps = {g["id"]: g for g in json.load(open(B + "/_p26_gaps_P26F.json"))}
ex = json.load(open(B + "/_p29_explain_P29A.json"))
pg = ex["per_gap"]

LEN = re.compile(r"^\(SYM_LEN_(.+?)_(rows|ids) != 0\)$")


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


def conditional(member, cond_lits):
    """(#profiles satisfying cond_lits, #of those that EVALUATE member)."""
    mi = EI.get(member)
    sel = []
    for m in MASKS:
        ok = True
        for e, p in cond_lits:
            j = EI.get(e)
            if j is None or j not in m or not (m[j] & (2 if p else 1)):
                ok = False; break
        if ok:
            sel.append(m)
    if mi is None:
        return len(sel), -1
    return len(sel), sum(1 for m in sel if mi in m)


tab = collections.Counter()
per_first = collections.Counter()
examples = collections.defaultdict(list)
for gid, r in pg.items():
    if r["walked"]:
        continue
    L = lits(gaps[gid]["node_constraint"])
    fb = r["first_bad"]
    # the emptiness literals the cube demands
    empt = [(e, p) for e, p in L if LEN.match(e) and not p]
    member = next((e for e, p in L if e.startswith(fb[:60])), fb)
    A, Bc = conditional(member, empt) if empt else (-1, -1)
    if not empt:
        cls = "no emptiness demanded in the cube"
    elif A == 0:
        cls = "the demanded EMPTINESS SET itself is never realised (A=0)"
    elif Bc == 0:
        cls = "EMPTINESS FORECLOSES the member: 0 of %d profiles evaluate it" % A
    else:
        cls = "member IS evaluated under the demanded emptiness (%d/%d)" % (Bc, A)
    tab[cls] += 1
    per_first[(r["first_bad_v"], cls)] += 1
    if len(examples[cls]) < 3:
        examples[cls].append((gid, member[:90], len(empt), A, Bc))

print("round-7 non-walking gaps:", sum(tab.values()))
for k, n in tab.most_common():
    print("   %-70s %5d" % (k[:70], n))
print()
for k, n in per_first.most_common(12):
    print("   %-16s %-64s %5d" % (k[0], k[1][:64], n))
print()
for c, exl in examples.items():
    print(c[:70])
    for e in exl:
        print("     gap=%s member=%s emptiness_lits=%d A=%d B=%d" % e)
print("P29-R7DIAG-DONE")
