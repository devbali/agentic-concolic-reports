#!/usr/bin/env python3
"""C25 — the foreclosure evidence that EXISTS on the four witness leaves, and
the direction it points in.

`_c25_mincond.py` establishes that no subset of a member's WALK PREFIX
forecloses it at any width (B over the FULL prefix is > 0 for every member of
every leaf, and B is monotone non-increasing in |C|, so no subset can reach 0).
But a width-3 C drawn from the WHOLE cube does exist for several members — its
literals simply sit LATER in the walk.  §16f forbids that on purpose ("two
members would foreclose each other in a cycle and the leaf would not be well
defined").  This measures, per leaf:

  * which members have such a backward/whole-cube C (|C| minimal, exhaustive);
  * whether the drop set is ACYCLIC — i.e. no literal of any chosen C belongs
    to a member that is itself dropped (a well-founded drop set);
  * A over the REDUCED cube (the leaf minus the acyclic drop set), which is
    exactly whether a run of the corpus would now WALK that leaf.

Read-only, offline, no src/ edit.  Nothing here is applied to anything.
"""
import itertools, json, os, pickle, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BITS = os.path.join(HERE, "_c25_mincond_bits.pkl")
CKPT = os.path.join(HERE, "_cov_c24_C24R2.ckpt.jsonl")
OUT = os.path.join(HERE, "_c25_backward.json")

st = pickle.load(open(BITS, "rb"))
EXPRS = st["exprs"]; N = st["n"]; TB = st["T"]; FB = st["F"]
EIDX = {e: i for i, e in enumerate(EXPRS)}
EB = [TB[j] | FB[j] for j in range(len(EXPRS))]
ALL = (1 << N) - 1
mask = lambda l: (TB if l[1] else FB)[EIDX[l[0]]]

f = open(CKPT); f.readline()
leaves = []
for line in f:
    r = json.loads(line); v = r.get("v") or {}
    for c in (v.get("combos") or []):
        leaves.append((r["k"], [(e, bool(o)) for e, o in c]))
f.close()


def A(lits):
    m = ALL
    for l in lits:
        m &= mask(l)
    return m


def minimal_any(lits, d):
    """exhaustive minimum |C| over ALL other literals of the leaf."""
    jd = EIDX[d]
    cands = [l for l in lits if l[0] != d]
    for r in range(1, len(cands) + 1):
        for sub in itertools.combinations(cands, r):
            m = A(sub)
            if m and not (m & EB[jd]):
                return list(sub), m.bit_count()
    return None


out = []
for li, (k, lits) in enumerate(leaves):
    print(f"\n=== LEAF {li}  key {k}  width {len(lits)} ===", flush=True)
    per = {}
    for pos, (e, o) in enumerate(lits):
        got = minimal_any(lits, e)
        if got:
            per[pos] = {"expr": e, "outcome": o, "C": got[0], "A": got[1],
                        "C_pos": sorted(lits.index(l) for l in got[0])}
    drop = set(per)
    # ACYCLIC core: iteratively remove any drop whose C names a dropped member
    while True:
        bad = {p for p in drop if any(q in drop for q in per[p]["C_pos"])}
        if not bad:
            break
        drop -= bad
    print(f"  members with a whole-cube C: {sorted(per)}", flush=True)
    for p in sorted(per):
        v = per[p]
        tag = "ACYCLIC" if p in drop else "ill-founded (its C names a dropped member)"
        print(f"    pos{p:2d} |C|={len(v['C'])} A={v['A']:6d} from pos {v['C_pos']}  [{tag}]",
              flush=True)
        print(f"        member {'T' if v['outcome'] else 'F'} {v['expr']}", flush=True)
        for x, y in v["C"]:
            print(f"            C: {'T' if y else 'F'}  {x}", flush=True)
    red = [l for i, l in enumerate(lits) if i not in drop]
    a_full = A(lits).bit_count()
    a_red = A(red).bit_count()
    print(f"  A(full leaf, {len(lits)} lits) = {a_full}", flush=True)
    print(f"  acyclic drop set = {sorted(drop)}  -> reduced leaf {len(red)} lits, "
          f"A(reduced) = {a_red}   "
          f"{'*** a run of the corpus WALKS the reduced leaf' if a_red else 'still A = 0'}",
          flush=True)
    out.append({"leaf": li, "key": k, "width": len(lits),
                "per_member": {str(p): {kk: (vv if kk != 'C' else [[x, y] for x, y in vv])
                                        for kk, vv in v.items()} for p, v in per.items()},
                "acyclic_drop": sorted(drop), "A_full": a_full,
                "reduced_width": len(red), "A_reduced": a_red})

json.dump(out, open(OUT, "w"), indent=1)
print("\nC25-BACKWARD-DONE", flush=True)
