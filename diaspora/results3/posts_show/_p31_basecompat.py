#!/usr/bin/env python3
"""P31 light phase — THE BASE-COMPATIBILITY CENSUS.

§89.10 localised round 8's failure: 1 636/1 636 contradicted literals are on
the length gate, and 566/569 seeds sat on a base that does NOT walk the cube's
enabling gates.  The rule the next constructor needs is

    a base is admissible for a cube only if the base ALREADY REALISES the
    cube's upstream EMPTINESS PINS (every list the cube pins EMPTY is empty on
    the base, every list it pins NON-EMPTY is non-empty) AND already WALKS
    every enabling gate of the cube's leaf group.

This script measures, per gap, how many bases in the corpus index satisfy each
half and both, so the hard filter's feasibility is known BEFORE it is switched
on.  Read-only; no drives, no Z3, no JRuby.
"""
import json, os, pickle, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")

GAPS = os.environ.get("P31_GAPS", os.path.join(HERE, "_p30_gaps_P30B.json"))
INDEX = os.environ.get("P31_INDEX", os.path.join(HERE, "_p30_index_P30B.pkl"))
OUT = os.environ.get("P31_OUT", os.path.join(HERE, "_p31_basecompat.json"))
MAN = os.environ.get("P31_MANIFEST", os.path.join(HERE, "_p15_manifest_P30B.json"))

_LENPIN = re.compile(r"^\(\s*(SYM_LEN_[A-Za-z0-9_]+)\s*!=\s*0\s*\)$")


def cube_literals(nc):
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
    for p in out:
        p = p.strip(); pol = True
        m = re.match(r"^Not\((.*)\)$", p, re.S)
        if m:
            p, pol = m.group(1).strip(), False
        res.append((p, pol))
    return res


def main():
    t0 = time.time()
    idx = pickle.load(open(INDEX, "rb"))
    exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
    LENS = idx["lens"]; LIDX = {L: i for i, L in enumerate(LENS)}
    dumps = idx["dumps"]
    NEC = {}
    for e, v in (idx.get("necess") or {}).items():
        nzs, zs = set(v["nz"]), set(v["z"])
        both = nzs & zs
        NEC[e] = {"nz": sorted(nzs - both), "z": sorted(zs - both)}
    gaps = json.load(open(GAPS))
    man = {m["gap"]: m for m in json.load(open(MAN))} if os.path.exists(MAN) else {}
    print(f"gaps {len(gaps)}  bases {len(dumps)}  exprs {len(exprs)}  lens {len(LENS)}",
          flush=True)

    # per-base masks, pulled out of the tuple once
    EM = [d[2] for d in dumps]; TM = [d[3] for d in dumps]
    CM = [d[5] for d in dumps]; L0 = [d[6] for d in dumps]; L1 = [d[7] for d in dumps]
    FM = [d[8] for d in dumps]
    PATH = [d[0] for d in dumps]; VAR = [d[1] for d in dumps]
    bypath = {os.path.basename(p): i for i, p in enumerate(PATH)}

    rows = []
    stat = Counter()
    unpinnable = Counter()          # length var -> gaps for which no base realises it
    gate_unwalkable = Counter()
    for g in gaps:
        nc = g["node_constraint"]
        lits = cube_literals(nc)
        # ---- (A) the cube's OWN length pins
        pins = {}
        conflict_self = False
        for e, pol in lits:
            m = _LENPIN.match(e)
            if m:
                L = m.group(1)
                if L in pins and pins[L] != pol:
                    conflict_self = True
                pins[L] = pol
        # ---- (B) the NECESSITY-derived upstream pins of the cube's literals
        npins = {}
        for e, _pol in lits:
            nv = NEC.get(e)
            if not nv:
                continue
            for L in nv["nz"]:
                npins.setdefault(L, True)
            for L in nv["z"]:
                npins.setdefault(L, False)
        # necessity pins that CONTRADICT the cube's own pins are not
        # realisable on any single base: they are the split-pin class.
        nec_conflict = sorted(L for L, w in npins.items()
                              if L in pins and pins[L] != w)
        # ---- (C) the enabling gates
        gates = g.get("gates") or {}

        pin_bits, pin_miss_name = [], []
        for L, w in pins.items():
            j = LIDX.get(L)
            if j is None:
                pin_miss_name.append(L)     # no base in the corpus mints it
                continue
            pin_bits.append((j, w))
        npin_bits = []
        for L, w in npins.items():
            if L in pins:
                continue
            j = LIDX.get(L)
            if j is not None:
                npin_bits.append((j, w))
        gate_bits, gate_miss_name = [], []
        for e, o in gates.items():
            j = eidx.get(e)
            if j is None:
                gate_miss_name.append(e)
                continue
            gate_bits.append((j, bool(o)))

        n_pin = n_gate = n_both = n_all = 0
        first_both = None
        per_pin_fail = Counter(); per_gate_fail = Counter()
        for i in range(len(dumps)):
            l0, l1, em, tm, fm = L0[i], L1[i], EM[i], TM[i], FM[i]
            okp = True
            for j, w in pin_bits:
                if ((l1 >> j) & 1) if w else ((l0 >> j) & 1):
                    continue
                okp = False; per_pin_fail[j] += 1
                break
            okg = True
            for j, o in gate_bits:
                if (((em & tm) >> j) & 1) if o else (((em & fm) >> j) & 1):
                    continue
                okg = False; per_gate_fail[j] += 1
                break
            if okp:
                n_pin += 1
            if okg:
                n_gate += 1
            if okp and okg:
                n_both += 1
                if first_both is None:
                    first_both = i
                okn = True
                for j, w in npin_bits:
                    if ((l1 >> j) & 1) if w else ((l0 >> j) & 1):
                        continue
                    okn = False; break
                if okn:
                    n_all += 1

        cls = ("full" if n_both else ("pins-only" if n_pin else
               ("gates-only" if n_gate else "none")))
        if n_both and n_all:
            cls = "full+nec"
        stat[cls] += 1
        stat["gaps"] += 1
        if not n_both:
            # what is missing
            if pin_miss_name:
                stat["missing: a pinned length no base mints"] += 1
            if gate_miss_name:
                stat["missing: a gate outside the demand universe"] += 1
            if n_pin and not n_gate:
                stat["missing: gates (pins realisable)"] += 1
            elif n_gate and not n_pin:
                stat["missing: pins (gates walkable)"] += 1
            elif not n_pin and not n_gate:
                stat["missing: both halves separately empty"] += 1
            else:
                stat["missing: each half alone OK, no base does BOTH"] += 1
            for j, c in per_pin_fail.items():
                if c == len(dumps):
                    unpinnable[LENS[j]] += 1
            for j, c in per_gate_fail.items():
                if c == len(dumps):
                    gate_unwalkable[exprs[j]] += 1

        oldbase = (man.get(g["id"], {}) or {}).get("base")
        old_i = bypath.get(os.path.basename(oldbase)) if oldbase else None
        old_pin = old_gate = None
        if old_i is not None:
            l0, l1, em, tm, fm = L0[old_i], L1[old_i], EM[old_i], TM[old_i], FM[old_i]
            old_pin = all((((l1 >> j) & 1) if w else ((l0 >> j) & 1)) for j, w in pin_bits)
            old_gate = all(((((em & tm) >> j) & 1) if o else (((em & fm) >> j) & 1))
                           for j, o in gate_bits)
        rows.append({"gap": g["id"], "set": g["set"], "width": g["width"],
                     "n_pins": len(pins), "n_necpins": len(npin_bits),
                     "n_gates": len(gates),
                     "pin_bases": n_pin, "gate_bases": n_gate,
                     "both_bases": n_both, "both_plus_nec_bases": n_all,
                     "class": cls,
                     "pins_no_base_mints": pin_miss_name,
                     "gates_outside_universe": gate_miss_name,
                     "nec_conflicts_cube": nec_conflict,
                     "self_conflicting_pins": conflict_self,
                     "round8_base": os.path.basename(oldbase) if oldbase else None,
                     "round8_base_pin_ok": old_pin, "round8_base_gate_ok": old_gate,
                     "example_base": os.path.basename(PATH[first_both]) if first_both is not None else None,
                     "example_base_variant": VAR[first_both] if first_both is not None else None})

    json.dump({"rows": rows, "stat": dict(stat),
               "unpinnable_lengths": dict(unpinnable),
               "unwalkable_gates": dict(gate_unwalkable)}, open(OUT, "w"))

    print("\nBASE-COMPATIBILITY, %d gaps against %d indexed bases" % (len(gaps), len(dumps)))
    for k in ("full+nec", "full", "pins-only", "gates-only", "none"):
        print("   %-12s %5d" % (k, stat.get(k, 0)))
    print("\nwhy the incompatible ones are incompatible:")
    for k, v in sorted(stat.items()):
        if k.startswith("missing"):
            print("   %-52s %5d" % (k, v))
    print("\nround-8's own base choice, re-scored under the new rule:")
    okp = sum(1 for r in rows if r["round8_base_pin_ok"])
    okg = sum(1 for r in rows if r["round8_base_gate_ok"])
    okb = sum(1 for r in rows if r["round8_base_pin_ok"] and r["round8_base_gate_ok"])
    kn = sum(1 for r in rows if r["round8_base_pin_ok"] is not None)
    print("   base known for %d/%d;  pins OK %d   gates OK %d   BOTH %d"
          % (kn, len(rows), okp, okg, okb))
    if unpinnable:
        print("\nlength variables NO base realises as the cube demands:")
        for L, c in unpinnable.most_common(12):
            print("   %-70s %4d gaps" % (L[:70], c))
    if gate_unwalkable:
        print("\nenabling gates NO base walks:")
        for e, c in gate_unwalkable.most_common(12):
            print("   %-70s %4d gaps" % (e[:70], c))
    nc = sum(1 for r in rows if r["nec_conflicts_cube"])
    print("\ngaps whose NECESSITY pins contradict their own cube pins "
          "(the split-pin class): %d" % nc)
    print("\nP31-BASECOMPAT-DONE %.0fs -> %s" % (time.time() - t0, OUT))


if __name__ == "__main__":
    main()
