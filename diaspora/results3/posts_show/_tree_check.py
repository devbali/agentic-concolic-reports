#!/usr/bin/env python3
"""Did the wanted side of each tree_missing target appear? — over a dump GLOB.

Routed through the engine's own load path (`coverage_report.canonicalize_ordinals`),
so the names compared here are the names the checker builds its universe from.
This is a fast per-round read; the JUDGE is still a coverage pass.

usage: _tree_check.py '<glob>' [more globs...]
"""
import glob, json, os, sys
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals, fix_len_names  # noqa: E402

# LEN-NAME FIX (2026-09-10, drive). The engine's load path is
# `canonicalize_ordinals(raw)` THEN `fix_len_names(raw)` — the second renames
# `len(X)` -> `SYM_LEN_X` because `len(X)` is not a valid Python identifier and
# coverage.py would otherwise drop the expr into `unevaluable_exprs`. These
# ported `_tree_*` tools applied only the FIRST, so every `SYM_LEN_*` target
# (4 of this endpoint's 11 tree_missing entries) matched NOTHING: the first
# full-corpus scan reported 0 evaluations for t01/t06/t08/t11 over 96 365
# dumps while the checker had them in `tree_missing`, which is only possible
# if the names differ. notifications' targets carried no `SYM_LEN_` name, so
# its copy never exercised this. `_demand_root.py` already handled both forms
# (its `fixed_to_orig` / `_seed_key`); these three did not.


TARGETS = json.load(open(os.path.join(HERE, "_tw", "targets.json")))
TEXPR = {t["expr"]: t["side"] for t in TARGETS}
files = []
for g in sys.argv[1:]:
    files += glob.glob(os.path.join(HERE, g))
print(f"scanning {len(files)} dumps")
hit = Counter(); other = Counter(); wit = {}
for p in files:
    try:
        d = json.load(open(p))
        canonicalize_ordinals(d)
        d = fix_len_names(d)
    except Exception:
        continue
    for e in d.get("events") or ():
        if e.get("type") != "path_condition":
            continue
        ex = e.get("expr")
        if ex in TEXPR:
            side = "taken" if e.get("taken") else "not_taken"
            if side == TEXPR[ex]:
                hit[ex] += 1
                wit.setdefault(ex, os.path.basename(p))
            else:
                other[ex] += 1
    del d
for i, t in enumerate(TARGETS, 1):
    e = t["expr"]
    print(f"t{i:02d} want={t['side']:9s} HIT={hit[e]:5d} other={other[e]:5d} "
          f"{'<-- CLOSED by '+wit[e] if hit[e] else ''}  {e[:110]}")
