#!/usr/bin/env python3
"""P27 phase 2 — CLASSIFY every model-less OR-refined region piece, and
RECOUNT the OR-refined residue with the FULL CONJUNCTION instead of the
component product.

Reads `_p27_state.jsonl` (written by `_p27_probe.py`); needs no corpus.

  1. CLASSIFY. For each piece `_emit_item` found no model for, re-issue the
     exact query it issued, with z3 directly, and report sat / unsat /
     unknown.  For unsat, extract the UNSAT CORE over tracked literals (each
     fixed-base constraint, each pin, each cube literal) and classify it.
     Three differentials separate the causes:
        drop the RENDER_IDENTITY equality  -> sat?  => cross-component coupling
        drop this set's pins               -> sat?  => pin over-restriction
        keep only the cube                 -> sat?  => the base, not the cube

  2. RECOUNT. For every leaf group, enumerate the cross product of the
     component model lists (that product IS the census's `cube_count`) and
     test each total assignment against the FULL conjunction.  sat_exact is
     the number that survive; covered_exact is how many of those lie in some
     observed cube.  remaining_exact = sat_exact - covered_exact, per set and
     in total.

  MODE=classify|recount|all   SAMPLE=n (classify only)  OUT=<prefix>
"""
import json
import os
import sys
import time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

import z3                                                            # noqa: E402
from concolic_engine.solver import _Z3_NAMESPACE                     # noqa: E402
from concolic_engine.coverage import (_combo_constraint,             # noqa: E402
                                      _outcome_constraint)

STATE = os.environ.get("STATE", os.path.join(HERE, "_p27_state.jsonl"))
MODE = os.environ.get("MODE", "all")
TIMEOUT = int(os.environ.get("Z3_TIMEOUT_MS", "10000"))
OUTP = os.environ.get("OUT", os.path.join(HERE, "_p27"))
RENDER_ID = "SYM_RESULT_Anonymous_process_2 == SYM_RESULT_Anonymous_process_3"

fh = open(STATE)
HDR = json.loads(fh.readline())
DECLS = HDR["decls"]
FIXED_BASE = HDR["fixed_base"]
PINNED = HDR["pinned"]
print(f"decls={len(DECLS)} fixed_base={len(FIXED_BASE)} pinned={len(PINNED)}")
print("fixed_base entries that mention >1 declared variable:")
_known = {d.split("=", 1)[0].strip() for d in DECLS}
import re                                                            # noqa: E402
_ID = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
CROSS = []
for c in FIXED_BASE:
    vs = {t for t in _ID.findall(c) if t in _known}
    if len(vs) > 1:
        CROSS.append((c, sorted(vs)))
for c, vs in CROSS:
    print(f"   CROSS-VAR {c}   vars={vs}")
print(f"  -> {len(CROSS)} cross-variable base constraint(s) of {len(FIXED_BASE)}")
CROSSSET = {c for c, _ in CROSS}

# ---- z3 plumbing -----------------------------------------------------------
ENV = dict(_Z3_NAMESPACE)
for d in DECLS:
    try:
        exec(d, {"__builtins__": {}}, ENV)
    except Exception as e:                                  # pragma: no cover
        print("DECL-FAIL", d, e)
_PC = {}


def parse(txt):
    if txt not in _PC:
        try:
            _PC[txt] = eval(txt, {"__builtins__": {}}, ENV)
        except Exception as e:
            _PC[txt] = ("PARSE-FAIL", str(e))
    return _PC[txt]


def status(constraints, timeout=TIMEOUT):
    s = z3.Solver()
    s.set("timeout", timeout)
    for c in constraints:
        p = parse(c)
        if isinstance(p, tuple):
            return "parsefail:" + c[:60]
        s.add(p)
    r = s.check()
    return "sat" if r == z3.sat else ("unsat" if r == z3.unsat else "unknown")


def core(constraints, timeout=TIMEOUT):
    """(status, [constraint strings in the unsat core])."""
    s = z3.Solver()
    s.set("timeout", timeout)
    tr = {}
    for i, c in enumerate(constraints):
        p = parse(c)
        if isinstance(p, tuple):
            return "parsefail:" + c[:60], []
        b = z3.Bool(f"__p27_t{i}")
        tr[b.get_id()] = c
        s.add(z3.Implies(b, p))
    ks = [z3.Bool(f"__p27_t{i}") for i in range(len(constraints))]
    r = s.check(*ks)
    if r == z3.sat:
        return "sat", []
    if r != z3.unsat:
        return "unknown", []
    return "unsat", [tr[b.get_id()] for b in s.unsat_core()]


def pins_of(group):
    return [_outcome_constraint(e, PINNED[e]) for e in group if e in PINNED]


# ---- load state ------------------------------------------------------------
t0 = time.time()
SETS = []
for line in fh:
    SETS.append(json.loads(line))
print(f"loaded {len(SETS)} set records in {time.time()-t0:.0f}s", flush=True)

# ============================ 1. CLASSIFY ===================================
if MODE in ("classify", "all"):
    rows = []
    cls = Counter()
    cls_by_width = defaultdict(Counter)
    t1 = time.time()
    nm = 0
    for rec in SETS:
        pins = pins_of(rec["group"])
        for g in rec["groups"]:
            for pc in g["pieces"]:
                if pc["ok"]:
                    continue
                nm += 1
                combo = sorted(pc["cube"].items())
                lits = [_outcome_constraint(e, o) for e, o in combo]
                q = FIXED_BASE + pins + [_combo_constraint(combo)]
                st = status(q)
                # tracked core over ATOMS (fixed base, pins, cube literals)
                atoms = FIXED_BASE + pins + lits
                cst, cr = core(atoms)
                d_norender = status([c for c in FIXED_BASE if c not in CROSSSET]
                                    + pins + lits)
                d_nopin = status(FIXED_BASE + lits)
                d_cubeonly = status(lits)
                if st == "unknown":
                    k = "C:z3-unknown"
                elif st == "sat":
                    k = "C:sat-but-no-model"
                elif d_norender == "sat":
                    k = "A1:cross-variable base constraint (component product invalid)"
                elif d_nopin == "sat":
                    k = "A2:pin over-restriction"
                elif d_cubeonly == "unsat":
                    k = "A3:cube self-contradictory"
                else:
                    k = "A4:other base conflict"
                cls[k] += 1
                cls_by_width[rec["width"]][k] += 1
                rows.append(dict(ci=rec["ci"], width=rec["width"],
                                 surv=len(g["surv"]), nlits=len(combo),
                                 n=pc["n"], status=st, core_status=cst,
                                 core=cr, d_norender=d_norender,
                                 d_nopin=d_nopin, d_cubeonly=d_cubeonly,
                                 cls=k, cube=pc["cube"]))
                if nm % 200 == 0:
                    print(f"   classified {nm} ({time.time()-t1:.0f}s)", flush=True)
    with open(OUTP + "_class.jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    print(f"\n=== CLASSIFICATION of {nm} model-less pieces "
          f"({time.time()-t1:.0f}s) ===")
    for k, v in cls.most_common():
        print(f"  {v:>6}  {k}")
    print("\n  by demand-set width:")
    for w in sorted(cls_by_width):
        print(f"   w={w:>2}: " + "; ".join(f"{k.split(':')[0]}={v}"
                                           for k, v in cls_by_width[w].most_common()))
    corec = Counter()
    for r in rows:
        sig = []
        for c in r["core"]:
            if c in CROSSSET:
                sig.append("CROSS-BASE")
            elif c in FIXED_BASE:
                sig.append("base")
            elif c in pins_of(next(s for s in SETS if s["ci"] == r["ci"])["group"]):
                sig.append("pin")
            else:
                sig.append("lit")
        corec[tuple(sorted(Counter(sig).items()))] += 1
    print("\n  unsat-core composition (multiset of atom kinds):")
    for k, v in corec.most_common(12):
        print(f"   {v:>6}  {dict(k)}")

# ============================ 2. RECOUNT ====================================
if MODE in ("recount", "all"):
    t2 = time.time()
    memo = {}

    def conj_sat(lits, pins):
        key = (tuple(lits), tuple(pins))
        if key not in memo:
            memo[key] = status(FIXED_BASE + list(pins) + list(lits))
        return memo[key]

    tot_sat = tot_cov = 0
    tot_sat_x = tot_cov_x = 0
    per = []
    ncalls = 0
    for si, rec in enumerate(SETS):
        pins = tuple(pins_of(rec["group"]))
        s_x = c_x = 0
        for g in rec["groups"]:
            comps = [(tuple(k), m) for k, m in g["comps"]]
            pre = g["pre"]
            # per-component model lists filtered by the prefix
            filt = []
            for k, models in comps:
                keep = [m for m in models
                        if all(pre[e] == m[e] for e in k if e in pre)]
                filt.append(keep)
            if any(not f for f in filt):
                continue
            obs = [dict(o) for o in g["obs"]]
            # cross product
            stack = [{}]
            for keep in filt:
                nxt = []
                for partial in stack:
                    for m in keep:
                        d = dict(partial)
                        d.update(m)
                        nxt.append(d)
                stack = nxt
            for asg in stack:
                lits = tuple(sorted(_outcome_constraint(e, o)
                                    for e, o in asg.items()))
                st = conj_sat(lits, pins)
                ncalls += 1
                if st != "sat":
                    continue
                s_x += 1
                for o in obs:
                    if all(asg.get(e) == v for e, v in o.items()):
                        c_x += 1
                        break
        tot_sat += rec["sat"]
        tot_cov += rec["covered"]
        tot_sat_x += s_x
        tot_cov_x += c_x
        per.append(dict(ci=rec["ci"], width=rec["width"], sat=rec["sat"],
                        covered=rec["covered"], sat_x=s_x, cov_x=c_x))
        if si % 100 == 0:
            print(f"   recount [{si}/{len(SETS)}] z3={ncalls} memo={len(memo)} "
                  f"sat {tot_sat}->{tot_sat_x} rem "
                  f"{tot_sat-tot_cov}->{tot_sat_x-tot_cov_x} "
                  f"({time.time()-t2:.0f}s)", flush=True)
    json.dump(per, open(OUTP + "_recount.json", "w"))
    print(f"\n=== EXACT RECOUNT ({time.time()-t2:.0f}s, {ncalls} assignments, "
          f"{len(memo)} distinct queries) ===")
    print(f"  census  (component product): sat={tot_sat} covered={tot_cov} "
          f"REMAINING={tot_sat-tot_cov}")
    print(f"  exact   (full conjunction) : sat={tot_sat_x} covered={tot_cov_x} "
          f"REMAINING={tot_sat_x-tot_cov_x}")
    byw = defaultdict(lambda: [0, 0, 0, 0, 0])
    nz = nzx = 0
    for p in per:
        b = byw[p["width"]]
        b[0] += 1
        b[1] += p["sat"] - p["covered"]
        b[2] += p["sat_x"] - p["cov_x"]
        b[3] += p["sat"]
        b[4] += p["sat_x"]
        nz += (p["sat"] - p["covered"]) > 0
        nzx += (p["sat_x"] - p["cov_x"]) > 0
    print("  width  sets   sat(prod)  sat(exact)   rem(prod)  rem(exact)")
    for w in sorted(byw):
        b = byw[w]
        print(f"  {w:>5} {b[0]:>5} {b[3]:>11} {b[4]:>11} {b[1]:>11} {b[2]:>11}")
    print(f"  sets with remaining>0:  census {nz}   exact {nzx}")
print(f"P27-DIAG-DONE in {time.time()-t0:.0f}s")
