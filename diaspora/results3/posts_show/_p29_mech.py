#!/usr/bin/env python3
"""P29 step 2 — MECHANISM per never-evaluated key.

For each decision D that a round-6 cube demanded but the run never evaluated:
  1. NECESSITY (corpus, 48 368 profiles): every other decision E that is
     evaluated with ONE polarity in 100 % of the profiles that evaluate D.
     That is the enabling condition of D, measured, not guessed.
  2. Per failing gap: which necessary condition did the DUMP violate, and is
     that condition PINNED THE OTHER WAY BY THE CUBE ITSELF?
        cube-pins-against  -> the cube is unsatisfiable for a mechanical
                              reason; a declaration can retire it
        base-choice        -> only the base/seed put it there; drivable
"""
import json, os, pickle, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
M = pickle.load(open(HERE + "/_p29_decmatrix.pkl", "rb"))
E = M["exprs"]; ROWS = M["rows"]
EI = {e: i for i, e in enumerate(E)}
N = len(ROWS)
print("profiles", N, "decisions", len(E))

# mask per profile: dict idx->mask (1=F,2=T,3=both)
def evalers(i):
    return [r for r in ROWS if i in r[0]]


def necessity(dexpr, side=None):
    """Conditions holding in 100 % of profiles that EVALUATE dexpr (optionally
    only those that take it `side`)."""
    i = EI.get(dexpr)
    if i is None:
        return None, 0
    want = None if side is None else (2 if side else 1)
    sel = [r[0] for r in ROWS if i in r[0] and (want is None or (r[0][i] & want))]
    n = len(sel)
    if not n:
        return {}, 0
    # candidate: present in all, single polarity in all, same polarity
    cnt = collections.Counter()
    for m in sel:
        for j, v in m.items():
            cnt[(j, v)] += 1
    nec = {}
    for (j, v), c in cnt.items():
        if c == n and v in (1, 2) and j != i:
            nec[E[j]] = bool(v == 2)
    return nec, n


def main():
    per = json.load(open(HERE + "/_p29_perkey_P26F.json"))
    bad = [(g, r) for g, r in per.items() if not r["walked"]]
    targets = collections.Counter()
    for g, r in bad:
        f = next(l for l in r["lits"] if l["v"] != "honoured")
        if f["v"] == "never_evaluated":
            targets[(f["e"], f["p"])] += 1
    print("\ndistinct never-evaluated FIRST-BAD keys:", len(targets))
    out = {}
    for (expr, pol), n in targets.most_common():
        nec, ne = necessity(expr)
        necs, nes = necessity(expr, pol)
        out[expr + "|" + str(pol)] = {"n_gaps": n, "n_eval": ne,
                                      "n_eval_side": nes,
                                      "nec": nec, "nec_side": necs}
        print("\n=== %s   demand=%s   %d gaps" % (expr, pol, n))
        print("    profiles evaluating it: %d / %d   taking the demanded side: %d"
              % (ne, N, nes))
        print("    NECESSARY conditions of EVALUATING it (100%% of %d):" % ne)
        for k, v in sorted(nec.items()):
            print("        %-100s = %s" % (k[:100], v))
        extra = {k: v for k, v in necs.items() if k not in nec}
        if extra:
            print("    ADDITIONAL necessary conditions of taking it %s (100%% of %d):" % (pol, nes))
            for k, v in sorted(extra.items()):
                print("        %-100s = %s" % (k[:100], v))
    # per gap: which necessary condition did the run violate; is the cube against it
    print("\n\n=== PER GAP: violated necessity, and whether the CUBE pins against it ===")
    tab = collections.Counter()
    detail = collections.defaultdict(collections.Counter)
    for g, r in bad:
        f = next(l for l in r["lits"] if l["v"] != "honoured")
        if f["v"] != "never_evaluated":
            continue
        key = f["e"] + "|" + str(f["p"])
        nec = dict(out[key]["nec"]); nec.update(out[key]["nec_side"])
        cube = {l["e"]: l["p"] for l in r["lits"]}
        taken = r["taken"]
        viol = []
        for c, want in nec.items():
            t = taken.get(c)
            if t is None:
                viol.append((c, "not_evaluated_either", cube.get(c)))
            elif want not in t:
                viol.append((c, "run_took_opposite", cube.get(c)))
        against = [v for v in viol if v[2] is not None and v[2] != nec[v[0]]]
        if against:
            tab[(f["e"][:60], "CUBE-PINS-AGAINST-NECESSITY")] += 1
            for v in against:
                detail[f["e"][:60]][("AGAINST", v[0][:70])] += 1
        elif viol:
            tab[(f["e"][:60], "base/seed violated necessity (drivable)")] += 1
            for v in viol:
                detail[f["e"][:60]][(v[1], v[0][:70])] += 1
        else:
            tab[(f["e"][:60], "no necessity violated — unexplained")] += 1
    for k, n in tab.most_common():
        print("  %-62s %-42s %4d" % (k[0], k[1], n))
    print()
    for e, c in detail.items():
        print(" ", e)
        for k, n in c.most_common(10):
            print("      %-24s %-72s %4d" % (k[0], k[1], n))
    json.dump(out, open(HERE + "/_p29_mech.json", "w"), indent=1)
    print("\nP29-MECH-DONE")


main()
