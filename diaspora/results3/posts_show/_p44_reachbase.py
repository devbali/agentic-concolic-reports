#!/usr/bin/env python3
"""P44 — DOES A BASE THAT *REACHES* THE CUBE EXIST? The constructor's hard
filter is pins AND gates; "the base already EVALUATES the cube's literals" is
only rank term 3. 94 of 100 real misses failed because the chosen base never
evaluated the demanded member at all, so this asks the feasibility question the
filter never asks:

   how many bases satisfy  pins  AND  gates-walked  AND  evaluates every cube
   literal  --  and, separately, each weaker combination.

Read-only.  usage: python3 _p44_reachbase.py <gaps.json>
"""
import json, os, pickle, re, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
IDX = os.environ.get("P44_INDEX", os.path.join(HERE, "_p31_index_P35C.pkl"))
GAPS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_p31_gaps_P35C.json")
OUT = os.environ.get("P44_OUT", os.path.join(HERE, "_p44_reachbase.json"))

idx = pickle.load(open(IDX, "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
dumps = idx["dumps"]; LENS = idx["lens"]; LIDX = {L: i for i, L in enumerate(LENS)}
EM = [d[2] for d in dumps]; TM = [d[3] for d in dumps]; DFM = [d[8] for d in dumps]
DL0 = [d[6] for d in dumps]; DL1 = [d[7] for d in dumps]
gaps = json.load(open(GAPS))
print(f"{len(gaps)} gaps, {len(dumps)} bases", flush=True)

def lits(nc):
    out, depth, cur, i, n = [], 0, [], 0, len(nc or "")
    while i < n:
        c = nc[i]
        if c == "(": depth += 1
        elif c == ")": depth -= 1
        if depth == 0 and nc.startswith(" AND ", i):
            out.append("".join(cur)); cur = []; i += 5; continue
        cur.append(c); i += 1
    if cur: out.append("".join(cur))
    r = []
    for t in out:
        t = t.strip(); pol = True
        while t.startswith("Not(") and t.endswith(")"):
            t = t[4:-1].strip(); pol = not pol
        if t: r.append((t, pol))
    return r

C = Counter(); rows = []
for g in gaps:
    L = lits(g["node_constraint"])
    evm = tmask = fmask = 0
    ok = True
    for e, p in L:
        j = eidx.get(e)
        if j is None:
            ok = False; break
        evm |= 1 << j
        (tmask := tmask) if False else None
        if p: tmask |= 1 << j
        else: fmask |= 1 << j
    gt = gf = 0
    for e, p in (g.get("gates") or {}).items():
        j = eidx.get(e)
        if j is None: ok = False; break
        if p: gt |= 1 << j
        else: gf |= 1 << j
    if not ok:
        C["gap not expressible in the index universe"] += 1
        continue
    pins = {}
    for e, p in L:
        m = re.match(r"^\(\s*(SYM_LEN_[A-Za-z0-9_]+)\s*!=\s*0\s*\)$", e)
        if m: pins[m.group(1)] = bool(p)
    pin1 = pin0 = 0
    unmint = False
    for Lv, w in pins.items():
        j = LIDX.get(Lv)
        if j is None: unmint = True; continue
        if w: pin1 |= 1 << j
        else: pin0 |= 1 << j
    n_pins_ok = n_gates_ok = n_reach = n_all = n_realise = 0
    for i in range(len(dumps)):
        p_ok = ((DL1[i] & pin1) == pin1) and ((DL0[i] & pin0) == pin0)
        g_ok = ((TM[i] & gt) == gt) and ((DFM[i] & gf) == gf)
        r_ok = ((EM[i] & evm) == evm)
        w_ok = ((TM[i] & tmask) == tmask) and ((DFM[i] & fmask) == fmask)
        n_pins_ok += p_ok; n_gates_ok += g_ok; n_reach += r_ok
        n_all += (p_ok and g_ok and r_ok)
        n_realise += w_ok
    C["pins+gates+REACH base exists" if n_all else "NO pins+gates+REACH base"] += 1
    C["a base REALISES the whole cube (already covered)" if n_realise else
      "no base realises the cube (genuinely uncovered)"] += 1
    rows.append({"gap": g["id"], "set": g["set"], "width": len(L),
                 "bases_pins": n_pins_ok, "bases_gates": n_gates_ok,
                 "bases_reach": n_reach, "bases_pins_gates_reach": n_all,
                 "bases_realising": n_realise, "unminted_pin": unmint})
for k, n in C.most_common():
    print(f"   {n:6d}  {k}")
import statistics
a = [r["bases_pins_gates_reach"] for r in rows]
print(f"\nbases satisfying pins+gates+REACH: median {statistics.median(a):.0f}  "
      f"zero for {sum(1 for x in a if x == 0)} of {len(a)} gaps")
json.dump(rows, open(OUT, "w"), indent=1)
print("P44-REACHBASE-DONE")
