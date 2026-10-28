#!/usr/bin/env python3
"""P31 light phase — DOES THE GAP'S OWN ROUND-8 DUMP MAKE AN ADMISSIBLE BASE?

The ordinal-fixpoint round (§88.7) drove the contradicted class to 0 by using
the gap's OWN previous dump as base.  §89.10 showed the property that mattered
was not the provenance but that such a dump already realises the cube's
upstream pins.  Round 8 has now produced one dump per gap, so the branch is
testable: score each gap's own `*P30B*` dump against its cube pins and its
enabling gates, exactly as _p31_basecompat scores an indexed base.
"""
import json, os, re, sys, time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer     # noqa: E402
from coverage_assumptions import ALIASES                            # noqa: E402

GAPS = os.environ.get("P31_GAPS", os.path.join(HERE, "_p30_gaps_P30B.json"))
EXPL = os.environ.get("P31_EXPLAIN", os.path.join(HERE, "_p30_explain_P30B.json"))
COMPAT = os.environ.get("P31_COMPAT", os.path.join(HERE, "_p31_basecompat.json"))
OUT = os.environ.get("P31_OWNOUT", os.path.join(HERE, "_p31_owndump.json"))

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
_LENPIN = re.compile(r"^\(\s*(SYM_LEN_[A-Za-z0-9_]+)\s*!=\s*0\s*\)$")
sys.path.insert(0, HERE)
from _p31_basecompat import cube_literals                           # noqa: E402


def scan(path):
    d = json.load(open(path))
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rn = renamer(amap)
    lens = {}
    for s in d.get("symbolic_vars") or ():
        nm, val = s.get("name"), s.get("value")
        if nm is None or isinstance(val, (dict, list)):
            continue
        nm = fixlen(rn(str(nm)))
        if nm.startswith("SYM_LEN_") and nm.endswith("_rows"):
            lens[nm] = bool(val)
    t, f = set(), set()
    for e in ev:
        if e.get("type") != "path_condition":
            continue
        ex = fixlen(rn(str(e.get("expr", ""))))
        (t if e.get("taken") else f).add(ex)
    return lens, t, f


def main():
    t0 = time.time()
    gaps = {g["id"]: g for g in json.load(open(GAPS))}
    per = json.load(open(EXPL))["per_gap"]
    compat = {r["gap"]: r for r in json.load(open(COMPAT))["rows"]}
    st = Counter(); rows = []
    for n, (gid, g) in enumerate(sorted(gaps.items())):
        rec = per.get(gid)
        if not rec or not rec.get("dump"):
            st["no own dump"] += 1; continue
        p = os.path.join(HERE, rec["dump"])
        if not os.path.exists(p):
            st["own dump missing on disk"] += 1; continue
        lens, tset, fset = scan(p)
        pins = {}
        for e, pol in cube_literals(g["node_constraint"]):
            m = _LENPIN.match(e)
            if m:
                pins[m.group(1)] = pol
        pin_ok = True; pin_bad = []
        for L, w in pins.items():
            if L not in lens:
                pin_ok = False; pin_bad.append(L + " (unminted)")
            elif lens[L] != w:
                pin_ok = False; pin_bad.append(L + (" (want NZ, is Z)" if w else " (want Z, is NZ)"))
        gates = g.get("gates") or {}
        gate_ok = True; gate_bad = []
        for e, o in gates.items():
            if (e in tset) if o else (e in fset):
                continue
            gate_ok = False
            gate_bad.append(e + (" (not taken T)" if o else " (not taken F)"))
        st["own dump scored"] += 1
        st["own: pins OK"] += pin_ok
        st["own: gates OK"] += gate_ok
        st["own: BOTH"] += (pin_ok and gate_ok)
        st["own: BOTH | walked round8"] += (pin_ok and gate_ok and rec.get("walked", False))
        c = compat.get(gid, {})
        if pin_ok and gate_ok and c.get("class") != "full":
            st["own dump ADMISSIBLE where the index had none"] += 1
        rows.append({"gap": gid, "dump": rec["dump"], "walked": rec.get("walked"),
                     "pin_ok": pin_ok, "gate_ok": gate_ok,
                     "pin_bad": pin_bad, "gate_bad": gate_bad,
                     "index_class": c.get("class"), "index_both": c.get("both_bases")})
    json.dump({"rows": rows, "stat": dict(st)}, open(OUT, "w"))
    print("THE GAP'S OWN ROUND-8 DUMP AS A BASE (%d gaps)" % len(gaps))
    for k, v in sorted(st.items()):
        print("   %-48s %5d" % (k, v))
    nb = sum(1 for r in rows if not (r["pin_ok"] and r["gate_ok"]))
    pb = Counter()
    for r in rows:
        for x in r["pin_bad"]:
            pb["PIN " + x.split("_rows")[0][-38:] + x.split("_rows")[-1]] += 1
        for x in r["gate_bad"]:
            pb["GATE " + x[-58:]] += 1
    print("\n   %d not admissible; the failing pins/gates:" % nb)
    for k, v in pb.most_common(14):
        print("      %-72s %4d" % (k[:72], v))
    print("\nP31-OWNDUMP-DONE %.0fs -> %s" % (time.time() - t0, OUT))


if __name__ == "__main__":
    main()
