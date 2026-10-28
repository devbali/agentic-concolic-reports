#!/usr/bin/env python3
"""C13 — GROUND-TRUTH DIFFERENTIAL on this batch's own seeders, against the
three defects posts_show measured in `_construct_by_gate.py` (§77.4).

Not an instance test: for a sample of REAL base dumps and the REAL constrained
variables of the 777 C12 witness cubes, it resolves each variable to runtime
seed keys BOTH WAYS and compares the result against the base's OWN seed key set
(the keys the runtime demonstrably consumes on that run).

  OLD = `_construct_all.py`'s `ordinals()/_ordinals_raw()` (this batch's
        constructor since 2026-09-11)
  NEW = the derived round-trip (`_c13_construct.seedkeys`): a candidate is
        pushed back through the loader's own transforms and must come out as
        the checker name.

usage: SAMPLE=400 python3 -u _c13_defect_audit.py
"""
import json, os, random, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
import coverage_report as CR                                     # noqa: E402
from coverage_assumptions import ALIASES                         # noqa: E402
from _c13_construct import parse_cube                            # noqa: E402

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_pruned_20260911_143539.txt"))
N = int(os.environ.get("SAMPLE", "400"))

gaps = json.load(open(os.path.join(HERE, "_c13_gaps.json")))
varset = set()
for g in gaps:
    cons, unseed, pairs, bad = parse_cube(g["cube"])
    varset |= set(cons) | set(unseed)
    for a, _o, b, _w in pairs:
        varset.add(a); varset.add(b)
print(f"constrained variables across the 777 witness cubes: {len(varset)}")
print(f"  of them SYM_LEN_*: {sum(1 for v in varset if v.startswith('SYM_LEN_'))}")

files = [l.strip() for l in open(LIST) if l.strip()]
random.seed(7); files = random.sample(files, min(N, len(files)))

def old_ordinals(inv, canon):
    """_construct_all.ordinals + _ordinals_raw, verbatim in behaviour."""
    if canon.startswith("SYM_LEN_"):
        return ["len(" + k + ")" for k in _old_raw(inv, canon[8:])]
    return _old_raw(inv, canon)

def _old_raw(inv, canon):
    out = [o + canon[len(c):] for o, c in inv.items() if canon.startswith(c)]
    return sorted(set(out)) if out else [canon]

tot = Counter()
old_live_by, new_live_by = Counter(), Counter()
never_seedable = Counter()
for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rn = renamer(amap)
    seedkeys_of_base = set((d.get("concolic_seeds") or {}))
    inv = {o: c for o, c in (amap or {}).items()}
    rev = defaultdict(list)
    for o, c in (amap or {}).items():
        rev[c].append(o)
    rev_sorted = sorted(rev, key=len, reverse=True)
    del d

    def new_keys(k):
        dn = f"len({k[8:]})" if k.startswith("SYM_LEN_") else k
        outs = [dn]
        for c in rev_sorted:
            if re.search(re.escape(c) + r"(?![0-9])", dn):
                outs = [re.sub(re.escape(c) + r"(?![0-9])", o.replace("\\", "\\\\"), dn)
                        for o in rev[c]]
                break
        return [o for o in outs if fixlen(rn(o)) == k]

    for v in varset:
        tot["values"] += 1
        ok = old_ordinals(inv, v)
        nk = new_keys(v)
        old_live = [k for k in ok if k in seedkeys_of_base]
        new_live = [k for k in nk if k in seedkeys_of_base]
        tot["old_keys"] += len(ok); tot["new_keys"] += len(nk)
        tot["old_live"] += len(old_live); tot["new_live"] += len(new_live)
        if old_live:
            old_live_by[v] += 1
        if new_live:
            new_live_by[v] += 1
        if not old_live and not new_live:
            never_seedable[v] += 1
        if ok and not old_live:
            tot["old_values_all_keys_INERT"] += 1
        if not nk:
            tot["new_values_unresolvable_STATED"] += 1

n = len(files)
print(f"\nsample: {n} base dumps x {len(varset)} variables = {tot['values']} (variable, base) pairs")
print(f"  OLD (_construct_all): keys emitted {tot['old_keys']}, of which the base "
      f"actually consumes {tot['old_live']} "
      f"({100.0*tot['old_live']/max(1,tot['old_keys']):.1f} %)")
print(f"  NEW (derived round-trip): keys emitted {tot['new_keys']}, of which the base "
      f"actually consumes {tot['new_live']} "
      f"({100.0*tot['new_live']/max(1,tot['new_keys']):.1f} %)")
print(f"  OLD pairs where EVERY emitted key is INERT (silently written, never read): "
      f"{tot['old_values_all_keys_INERT']} "
      f"({100.0*tot['old_values_all_keys_INERT']/max(1,tot['values']):.1f} %)")
print(f"  NEW pairs the constructor STATES as not-seedable on that base: "
      f"{tot['new_values_unresolvable_STATED']} "
      f"({100.0*tot['new_values_unresolvable_STATED']/max(1,tot['values']):.1f} %)")
print(f"\n  variables NO sampled base can seed at all: "
      f"{sum(1 for v in varset if never_seedable[v] == n)} of {len(varset)}")
for v in sorted(varset):
    if never_seedable[v] == n:
        print(f"     {v[:110]}")
print(f"\n  variables at least one sampled base CAN seed: "
      f"OLD {sum(1 for v in varset if old_live_by[v])}, "
      f"NEW {sum(1 for v in varset if new_live_by[v])}")
diff = [v for v in varset if bool(old_live_by[v]) != bool(new_live_by[v])]
print(f"  variables where OLD and NEW DISAGREE on seedability: {len(diff)}")
for v in diff[:20]:
    print(f"     old={old_live_by[v]:4d} new={new_live_by[v]:4d}  {v[:100]}")
print("C13-DEFECT-AUDIT-DONE")
