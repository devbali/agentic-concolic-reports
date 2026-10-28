#!/usr/bin/env python3
"""P31 light phase — WHAT THE HARD FILTER CAN ACTUALLY DEMAND.

_p31_basecompat measured that only 189/569 gaps have a base that realises the
cube's emptiness pins AND walks the whole enabling-gate prefix.  This script
separates the two halves properly:

  * every LENGTH gate is already an emptiness pin, so it is inside HARD-1;
  * the residual gates are guid / find_by / has_mention decisions, which ARE
    seedable — the base only has to REACH them, not already take them.

so it measures, restricted to the pin-realising bases, how much of the residual
gate prefix the best base walks, and whether the shortfall is on a seedable
literal (recoverable by the seed) or not.
"""
import json, os, pickle, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from _p31_basecompat import cube_literals                            # noqa: E402

GAPS = os.environ.get("P31_GAPS", os.path.join(HERE, "_p30_gaps_P30B.json"))
INDEX = os.environ.get("P31_INDEX", os.path.join(HERE, "_p30_index_P30B.pkl"))
OUT = os.environ.get("P31_DIAGOUT", os.path.join(HERE, "_p31_gapdiag.json"))
_LENPIN = re.compile(r"^\(\s*(SYM_LEN_[A-Za-z0-9_]+)\s*!=\s*0\s*\)$")


def main():
    t0 = time.time()
    idx = pickle.load(open(INDEX, "rb"))
    exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
    LENS = idx["lens"]; LIDX = {L: i for i, L in enumerate(LENS)}
    dumps = idx["dumps"]
    seedable = set(idx.get("seedable") or ())
    EM = [d[2] for d in dumps]; TM = [d[3] for d in dumps]
    L0 = [d[6] for d in dumps]; L1 = [d[7] for d in dumps]; FM = [d[8] for d in dumps]
    gaps = json.load(open(GAPS))

    def var_of(e):
        m = re.match(r"^\(\s*([A-Za-z0-9_]+)\s*(==|!=)", e)
        return m.group(1) if m else None

    rows = []; st = Counter(); short = Counter()
    for g in gaps:
        lits = cube_literals(g["node_constraint"])
        pins = {}
        for e, pol in lits:
            m = _LENPIN.match(e)
            if m:
                pins[m.group(1)] = pol
        gates = g.get("gates") or {}
        lgates = {e: o for e, o in gates.items() if _LENPIN.match(e)}
        rgates = {e: o for e, o in gates.items() if not _LENPIN.match(e)}
        # HARD-1 consistency: every length gate must agree with the cube pin
        bad = [e for e, o in lgates.items()
               if pins.get(_LENPIN.match(e).group(1)) not in (None, o)]
        st["length gate disagrees with cube pin"] += bool(bad)

        pin_bits, unminted = [], []
        for L, w in pins.items():
            j = LIDX.get(L)
            if j is None:
                unminted.append(L); continue
            pin_bits.append((j, w))
        rg_bits = []
        for e, o in rgates.items():
            j = eidx.get(e)
            if j is not None:
                rg_bits.append((j, bool(o), e))

        best = -1; best_i = None; best_miss = None; npin = 0
        for i in range(len(dumps)):
            l0, l1 = L0[i], L1[i]
            ok = True
            for j, w in pin_bits:
                if ((l1 >> j) & 1) if w else ((l0 >> j) & 1):
                    continue
                ok = False; break
            if not ok:
                continue
            npin += 1
            em, tm, fm = EM[i], TM[i], FM[i]
            m = 0; miss = []
            for j, o, e in rg_bits:
                if (((em & tm) >> j) & 1) if o else (((em & fm) >> j) & 1):
                    m += 1
                else:
                    miss.append(e)
            if m > best:
                best, best_i, best_miss = m, i, miss
                if m == len(rg_bits):
                    break
        rec = {"gap": g["id"], "set": g["set"],
               "pins": len(pins), "unminted_pins": unminted,
               "len_gates": len(lgates), "residual_gates": len(rg_bits),
               "pin_bases": npin, "best_residual_match": best,
               "residual_shortfall": best_miss or [],
               "base": os.path.basename(dumps[best_i][0]) if best_i is not None else None,
               "variant": dumps[best_i][1] if best_i is not None else None}
        if npin == 0:
            st["NO base realises the emptiness pins"] += 1
        elif best == len(rg_bits):
            st["pin-realising base walks EVERY residual gate"] += 1
        else:
            st["pin-realising base, residual gate shortfall"] += 1
            for e in best_miss:
                v = var_of(e)
                short[("SEEDABLE   " if v in seedable else "unseedable ") + e[-56:]] += 1
        rows.append(rec)

    json.dump({"rows": rows, "stat": dict(st), "shortfall": dict(short)}, open(OUT, "w"))
    print("HARD-1 = the cube's emptiness pins;  residual gates = the non-length prefix")
    for k, v in sorted(st.items()):
        print("   %-52s %5d" % (k, v))
    tot = Counter(r["best_residual_match"] - r["residual_gates"] for r in rows)
    print("\n   residual-gate shortfall of the best pin-realising base:")
    for k in sorted(tot, reverse=True):
        print("      %+d gates   %4d gaps" % (k, tot[k]))
    print("\n   the missing residual gates, and whether a seed can steer them:")
    for k, v in short.most_common(14):
        print("      %-74s %4d" % (k[:74], v))
    print("\nP31-GAPDIAG-DONE %.0fs -> %s" % (time.time() - t0, OUT))


if __name__ == "__main__":
    main()
