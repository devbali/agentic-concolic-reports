#!/usr/bin/env python3
"""P44 — THE FORECLOSURE GATE ON THE *DRIVER'S* CONSTRUCTOR.

The 17.9 % positive-control rate that made 87 of 95 foreclosure classes
NOT-TESTABLE belongs to `foreclosure_gate.py` + `assumption_checker.py`'s probe
path. `_p31_construct.py` targets at 94.3 % (hold-out verified). This builds the
gate's two arms AS ORDINARY GAP RECORDS so the strong constructor, the ordinary
driver and `_p15_explain.py` do the work, and `src/` is not touched.

Per cube K that a targeted attempt failed to cover:
    d   = the literal the run never reached (or contradicted)
    C   = every OTHER literal of K, at K's demanded outcome
    claim   : "no run realises C and evaluates d"   -- the CLAIM arm is K itself
    control : C plus `d_ctl`, a demand-universe expression the corpus
              DEMONSTRABLY evaluates in runs that realise C, at the outcome
              those runs take.  The control shares the hard part (realising C)
              and differs only in the member, exactly as X11 requires.

Writes the CONTROL arm as a gaps file plus a join.  The CLAIM arm is the cube
itself and is driven separately.

  usage: _p44_gate_build.py <gaps.json> <explain.json> <out_ctrl.json> <out_join.json>
"""
import json, os, pickle, re, sys
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
IDX = os.environ.get("P44_INDEX", os.path.join(HERE, "_p44_index_UNION.pkl"))
GAPS, EXPL, OUTC, OUTJ = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

idx = pickle.load(open(IDX, "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
dumps = idx["dumps"]; domain = idx["domain"]
RAW = {tuple(k.split("\x00", 1)): v for k, v in idx["raw"].items()}
seedable = set(idx.get("seedable") or ())
EM = [d[2] for d in dumps]; TM = [d[3] for d in dumps]; DFM = [d[8] for d in dumps]
N = len(dumps)

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

_ID = r"[A-Za-z_][A-Za-z0-9_]*"
_EQ = re.compile(rf"^\(\s*({_ID})\s*==\s*(.+?)\s*\)$")
_NE = re.compile(rf"^\(\s*({_ID})\s*!=\s*(.+?)\s*\)$")
_LN = re.compile(rf"^\(\s*Length\(({_ID})\)\s*<\s*(\d+)\s*\)$")
def cvars(nc):
    out = set()
    for e, _p in lits(nc):
        for rx in (_EQ, _NE, _LN):
            m = rx.match(e)
            if not m: continue
            if rx is not _LN and m.group(2).strip() == m.group(1): break
            out.add(m.group(1)); break
    return out

gaps = {g["id"]: g for g in json.load(open(GAPS))}
pg = json.load(open(EXPL))["per_gap"]

ctrl, join = [], []
stat = Counter()
for gid, r in pg.items():
    if r["walked"]:
        stat["cube COVERED by the targeted attempt (no claim to test)"] += 1
        continue
    g = gaps[gid]
    d = r["first_bad"]
    L = lits(g["node_constraint"])
    C = [(e, p) for e, p in L if e != d]
    js, ok = [], True
    tm_req = fm_req = 0
    for e, p in C:
        j = eidx.get(e)
        if j is None:
            ok = False; break
        js.append(j)
        if p: tm_req |= 1 << j
        else: fm_req |= 1 << j
    if not ok:
        stat["NOT-TESTABLE: C is not expressible in the index universe"] += 1
        join.append({"gap": gid, "verdict_pre": "C not expressible"}); continue
    sel = [i for i in range(N) if (TM[i] & tm_req) == tm_req and (DFM[i] & fm_req) == fm_req]
    if not sel:
        stat["NOT-TESTABLE: no corpus run realises C, so no control exists"] += 1
        join.append({"gap": gid, "verdict_pre": "no corpus run realises C"}); continue
    dj = eidx.get(d)
    cnt = Counter()
    for i in sel:
        em = EM[i]
        for j in range(len(exprs)):
            if j == dj or j in js: continue
            if (em >> j) & 1: cnt[j] += 1
    if not cnt:
        stat["NOT-TESTABLE: runs realising C evaluate nothing else"] += 1
        join.append({"gap": gid, "verdict_pre": "no control member"}); continue
    cj, cn = cnt.most_common(1)[0]
    pol = sum(1 for i in sel if (TM[i] >> cj) & 1) >= sum(1 for i in sel if (DFM[i] >> cj) & 1)
    nc = " AND ".join([(e if p else f"Not({e})") for e, p in C]
                      + [exprs[cj] if pol else f"Not({exprs[cj]})"])
    model = {k: v for k, v in (g.get("concrete_values") or {}).items() if k in cvars(nc)}
    con = cvars(nc)
    ctrl.append({"id": f"k{len(ctrl):06d}", "set": g["set"], "width": g["width"],
                 "surviving": g.get("surviving", 0), "gates": g.get("gates") or {},
                 "part_family": g["part_family"], "families": g["families"],
                 "node_constraint": nc, "concrete_values": model, "assignments": None,
                 "constrained": sorted(con & set(model)), "out_of_domain": [],
                 "out_of_domain_free": [], "unknown_vars": [], "unknown_free": [],
                 "not_seedable": sorted(v for v in con if v in model and v not in seedable)})
    join.append({"gap": gid, "ctrl": ctrl[-1]["id"], "d": d,
                 "d_ctl": exprs[cj], "d_ctl_pol": bool(pol),
                 "bases_realising_C": len(sel), "control_support": cn,
                 "claim_dump": r["dump"]})
    stat["TESTABLE: control built"] += 1

json.dump(ctrl, open(OUTC, "w"))
json.dump(join, open(OUTJ, "w"))
for k, n in stat.most_common():
    print(f"   {n:6d}  {k}")
print(f"wrote {len(ctrl)} control gaps -> {os.path.basename(OUTC)}")
print("P44-GATE-BUILD-DONE")
