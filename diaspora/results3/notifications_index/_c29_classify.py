#!/usr/bin/env python3
"""C29 — classify this round's own dumps against the two cubes, per literal.

Reading is the checker's: alias map -> canonicalize_ordinals (which carries
split_self_compare) -> fix_len_names spelling.  A literal is REALISED in a run
iff the run recorded that expression with that outcome at least once.

  usage: TAG=C29A CUBE=on python3 -u _c29_classify.py
"""
import collections, glob, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for            # noqa: E402
import coverage_report as CR                                     # noqa: E402
from coverage_assumptions import ALIASES                         # noqa: E402
from _c29_dispatch import ON, OFF, P, V, DV, PH                  # noqa: E402

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
TAG = os.environ.get("TAG", "C29A")
CUBE = ON if os.environ.get("CUBE", "on") == "on" else OFF
PERS = f"({V}_row_target_persisted == True)"
TXT = f"({V}_row_target_text_nil == True)"
EXTRA = [(PERS, False), (TXT, True), (f"({PH} != 0)", None)]

files = sorted(glob.glob(os.path.join(HERE, f"dump_*_{TAG}*.json")))
print(f"tag {TAG}: {len(files)} dumps; cube width {len(CUBE)}")
per_lit = collections.Counter(); per_lit_ev = collections.Counter()
extra_ev = collections.Counter()
full = 0
errs = collections.Counter()
partial = collections.Counter()
for p in files:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    ev = d.get("events") or []
    alias_map_for([(e.get("result_name"), e.get("note"))
                   for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    CR.canonicalize_ordinals(d)
    rec = collections.defaultdict(set)
    for e in d.get("events") or []:
        if e.get("type") == "path_condition":
            rec[fixlen(str(e.get("expr", "")))].add(bool(e.get("taken")))
    err = (d.get("error") or {})
    errs[(err.get("type") or "<none>")] += 1
    ok = 0
    for e, o in CUBE:
        if e in rec:
            per_lit_ev[e] += 1
        if o in rec.get(e, ()):
            per_lit[e] += 1
            ok += 1
    partial[ok] += 1
    if ok == len(CUBE):
        full += 1
        print(f"   *** FULL CUBE REALISED: {os.path.basename(p)}")
    for e, o in EXTRA:
        if e in rec:
            extra_ev[e] += 1
            if o is not None and o in rec[e]:
                extra_ev[e + "  @want"] += 1
print(f"\nruns realising the WHOLE cube: {full} / {len(files)}")
print("runs by number of cube literals realised:",
      sorted(partial.items(), reverse=True))
print("\nper literal (realised / evaluated):")
for e, o in CUBE:
    print(f"  {'T' if o else 'F'}  {per_lit[e]:5d} / {per_lit_ev[e]:5d}   {e[:104]}")
print("\nenabling gates in this round's runs:")
for k, v in extra_ev.most_common():
    print(f"  {v:5d}  {k[:110]}")
print("\ndump errors:", errs.most_common())
print("C29-CLASSIFY-DONE")
