#!/usr/bin/env python3
"""Independent tree-layer census, straight off a dump list, through the
ENGINE'S OWN load path (canonicalize_ordinals + fix_len_names).

Reports, without a solver: every canonical tracked expression, which SIDES the
population observed, which are ONE-SIDED (tree-gap candidates before Z3
satisfiability), and the fate of the 7 ARGUMENT P pins and the 11 `_tw` tree
targets. This is §28's method, re-run; it is a CROSS-CHECK, never a substitute
for a coverage pass's own TREE_MISSING.

usage: DUMP_LIST=<snapshot> _tree_census.py [--tag <label substring>]
"""
import glob, json, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals, fix_len_names  # noqa: E402
import coverage_assumptions as CA  # noqa: E402

PINNED = {a.expr: a.tracked_side for a in CA._OVERNIGHT_PINS}
TW = {t["expr"]: t["side"] for t in json.load(open(os.path.join(HERE, "_tw", "targets.json")))}

def opt(n, d=None):
    return sys.argv[sys.argv.index(n) + 1] if n in sys.argv else d

TAG = opt("--tag")
_l = os.environ.get("DUMP_LIST")
dumps = ([l.strip() for l in open(_l) if l.strip()] if _l
         else sorted(glob.glob(os.path.join(HERE, "dump_*.json"))))
dumps = [d if os.path.isabs(d) else os.path.join(HERE, d) for d in dumps]
if TAG:
    dumps = [d for d in dumps if TAG in os.path.basename(d)]
print(f"population: {len(dumps)} dumps" + (f" (tag {TAG})" if TAG else ""))

sides = defaultdict(set)
for i, p in enumerate(dumps):
    try:
        d = json.load(open(p))
        canonicalize_ordinals(d); d = fix_len_names(d)
    except Exception:
        continue
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            sides[e["expr"]].add(bool(e.get("taken")))
    del d
    if i % 20000 == 19999:
        print(f"  ... {i+1}/{len(dumps)}", flush=True)

one = {k: v for k, v in sides.items() if len(v) == 1}
print(f"\ndistinct tracked exprs: {len(sides)}")
print(f"observed on ONE side only (tree-gap CANDIDATES, pre-Z3): {len(one)}")
print(f"  of those PINNED by ARGUMENT P: {sum(1 for k in one if k in PINNED)}")
print(f"  NOT pinned, still one-sided:   {sum(1 for k in one if k not in PINNED)}")

print("\n== THE 7 ARGUMENT P PINS ==")
for e, ts in sorted(PINNED.items()):
    obs = sides.get(e)
    # `tracked_side` is the side the pin KEEPS. The pin's claim is that the
    # OTHER side has no producing path, so the falsifier is the other side:
    # tracked_side="not_taken" -> the claimed-unreachable side is `taken`=True.
    falsifier = (ts == "not_taken")
    if obs is None:
        st = "NOT EVALUATED in this population"
    elif falsifier in obs:
        st = (f"*** FALSIFIED: the claimed-unreachable side WAS OBSERVED "
              f"-> DELETE THIS PIN ***  observed={sorted(obs)}")
    else:
        st = f"HOLDS (only {sorted(obs)}; falsifying side {falsifier} never seen)"
    print(f"  {e[:78]:78s} {st}")

print("\n== THE 11 _tw TREE TARGETS ==")
for e, side in sorted(TW.items(), key=lambda x: x[0]):
    obs = sides.get(e)
    want = (side == "taken")
    st = ("NOT EVALUATED" if obs is None
          else ("HIT (wanted side observed)" if want in obs
                else f"other side only {sorted(obs)}"))
    print(f"  want={side:9s} {st:30s} {e[:70]}")

print("\n== NOT-PINNED ONE-SIDED (the tree residual this population shows) ==")
res = sorted(k for k in one if k not in PINNED)
for k in res[:60]:
    print(f"  observed {sorted(one[k])}  {k[:110]}")
print(f"  ... total {len(res)}")
print(f"\nCENSUS_EXPRS={len(sides)} ONE_SIDED={len(one)} "
      f"ONE_SIDED_UNPINNED={len(res)}")
