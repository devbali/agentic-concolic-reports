#!/usr/bin/env python3
"""P44 BASE-REACH PROBE (read-only, no writes to any shared artifact).

Question it answers, mechanically, against the SAME index `_p31_construct.py`
uses: for the CLASSBV1 "size gate" gaps, does a base exist in the construct
index that BOTH (a) itself EVALUATES the blocked size-gate literal, and (b)
satisfies the cube's own emptiness pins (HARD-1)?

If YES -> the 0/4111 walk rate is a BASE-SELECTION STEERING gap and a scoring
          change can fix it.
If NO  -> the index lacks a compatible base; no scoring change can help and the
          remedy is driving (or the pair is genuinely foreclosed).

Env: P44_INDEX (default _p31_index_P35C.pkl), P44_GAPS (default
     _p44_gaps_CLASSBV1.json), P44_SIZERE (family regex).
"""
import json, os, pickle, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.environ.get("P44_INDEX", os.path.join(HERE, "_p31_index_P35C.pkl"))
GAPS = os.environ.get("P44_GAPS", os.path.join(HERE, "_p44_gaps_CLASSBV1.json"))
SIZERE = re.compile(os.environ.get("P44_SIZERE", r"CollectionProxy_size_\d+_size"))
MAXG = int(os.environ.get("P44_MAXG", "0"))          # 0 = all


def cube_literals(nc):
    """Verbatim copy of _p31_construct.py:197 (importing it would run main())."""
    out, depth, cur, i, n = [], 0, [], 0, len(nc or "")
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


_LENRE = re.compile(r"^\(\s*(SYM_LEN_[A-Za-z0-9_]+)\s*!=\s*0\s*\)$")


def main():
    t0 = time.time()
    idx = pickle.load(open(INDEX, "rb"))
    exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
    dumps = idx["dumps"]
    LENS = idx["lens"]; LIDX = {L: i for i, L in enumerate(LENS)}
    print(f"index {os.path.basename(INDEX)}: {len(dumps)} bases, {len(exprs)} exprs, "
          f"{len(LENS)} length vars  ({time.time()-t0:.0f}s)", flush=True)

    # ---- the size-gate expressions this index carries at all
    size_exprs = [(e, i) for e, i in eidx.items() if SIZERE.search(e)]
    print(f"\n== size-gate expressions present in the index: {len(size_exprs)}")
    for e, i in sorted(size_exprs):
        ev = sum(1 for d in dumps if (d[2] >> i) & 1)
        tr = sum(1 for d in dumps if ((d[2] & d[3]) >> i) & 1)
        print(f"   [{i:4d}] evaluated in {ev:6d}/{len(dumps)} bases  (true in {tr})  {e}")
    if not size_exprs:
        print("   NONE. The construct index cannot see this call site at all.")

    gaps = json.load(open(GAPS))
    if MAXG:
        gaps = gaps[:MAXG]
    print(f"\ngaps loaded: {len(gaps)} from {os.path.basename(GAPS)}", flush=True)

    # ---- per-gap: the size-gate literal it demands + its own emptiness pins.
    # Gaps are first bucketed into (size-gate literal set, pin signature)
    # CLASSES; the 48943-base scan then runs once per class, not per gap.
    stat = Counter()
    cls_gaps = defaultdict(list)
    cls_info = {}
    for g in gaps:
        cl = cube_literals(g["node_constraint"])
        sg = [(e, o) for e, o in cl if SIZERE.search(e)]
        if not sg:
            stat["gaps with NO size-gate literal"] += 1
            continue
        stat["gaps WITH a size-gate literal"] += 1
        pins = {}
        for e, o in cl:
            m = _LENRE.match(e)
            if m:
                pins[m.group(1)] = bool(o)      # True = non-empty demanded
        # candidate bases:
        #   A = satisfies the cube's emptiness pins (HARD-1 as _p31 applies it)
        #   B = itself evaluates EVERY size-gate literal of the cube
        #   A&B = what a reach-aware base filter would need to exist
        sbits = []
        missing_expr = False
        for e, o in sg:
            j = eidx.get(e)
            if j is None:
                missing_expr = True
                break
            sbits.append(j)
        if missing_expr:
            stat["gaps whose size-gate expr is NOT in the index"] += 1
            continue
        key = (tuple(sorted(sbits)), tuple(sorted(pins.items())))
        cls_gaps[key].append(g["id"])
        cls_info[key] = (sbits, pins)

    print("\n== PER-GAP BUCKETING ==")
    for k, v in stat.most_common():
        print(f"   {v:6d}  {k}")
    print(f"   {len(cls_gaps)} distinct (size-gate literal set, pin signature) classes")

    # ---- one 48943-base scan per class
    print("\n== PER-CLASS BASE AVAILABILITY ==", flush=True)
    print("   A  = bases satisfying the cube's OWN emptiness pins (HARD-1)")
    print("   B  = bases that themselves EVALUATE every size-gate literal")
    print("   AB = bases satisfying BOTH -> what a reach-aware filter needs\n")
    tot_with = tot_without = 0
    rows = []
    for key in sorted(cls_gaps, key=lambda k: -len(cls_gaps[k])):
        sbits, pins = cls_info[key]
        pin_bits, unminted = [], 0
        for L, w in pins.items():
            j = LIDX.get(L)
            if j is None:
                unminted += 1
            else:
                pin_bits.append((j, w))
        nA = nB = nAB = 0
        ab_examples = []
        for d in dumps:
            # dumps tuple layout, per _p31_construct.py:685
            #   (path, var, em, tm, ns, cm, dl0, dl1, dfm)
            em, dl0, dl1 = d[2], d[6], d[7]
            ok = True
            for j, w in pin_bits:
                if ((dl1 >> j) & 1) if w else ((dl0 >> j) & 1):
                    continue
                ok = False
                break
            ev = all((em >> j) & 1 for j in sbits)
            if ok:
                nA += 1
            if ev:
                nB += 1
            if ok and ev:
                nAB += 1
                if len(ab_examples) < 3:
                    ab_examples.append(os.path.basename(d[0]))
        ng = len(cls_gaps[key])
        if nAB:
            tot_with += ng
        else:
            tot_without += ng
        rows.append((ng, nA, nB, nAB, len(pins), unminted, sbits, ab_examples,
                     cls_gaps[key][:2]))
    for ng, nA, nB, nAB, npin, unm, sbits, ex, gids in rows[:25]:
        print(f"   gaps={ng:5d}  A={nA:6d}  B={nB:6d}  AB={nAB:6d}  "
              f"pins={npin} (unminted {unm})  sgbits={sbits}  ex={ex}  {gids}")

    print(f"\n== VERDICT ==")
    print(f"   gaps WITH at least one compatible base : {tot_with}")
    print(f"   gaps WITHOUT any compatible base       : {tot_without}")
    if tot_with:
        print("   -> a compatible base EXISTS in the index: the 0-walk rate on "
              "those gaps is a BASE-SELECTION STEERING gap, fixable by scoring.")
    if tot_without and not tot_with:
        print("   -> NO compatible base in the index: scoring cannot help; the "
              "remedy is driving or the pair is foreclosed.")

    print(f"\ndone {time.time()-t0:.0f}s")


main()
