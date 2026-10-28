#!/usr/bin/env python3
"""ROOTED seeds for the tree_missing branch outcomes.

Bulk variation reaches a branch only if a random seed happens to land in the
context that evaluates it. These ten sites are reached by 3 to 18 321 runs of
109 401, so bulk is the wrong instrument for the rare ones. This builds, for
each target, seeds that are a REAL DUMP'S OWN SEEDS (a run that provably
evaluated the expression, on the other side) with EXACTLY the target
dimension flipped — the context is reproduced, one decision moves.

Canonical -> ordinal is taken from the BASE DUMP'S OWN alias map, and EVERY
ordinal backing the canonical is seeded (the map is many-to-one by design;
picking one contradicts the demand whenever the path takes another —
`_demand_root.py`'s 2026-09-09 fix, same defect).

writes _treeR_<variant>.json ; usage: _tree_root.py [--bases N]
"""
import json, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals  # noqa: E402

VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
NB = int(sys.argv[sys.argv.index("--bases") + 1]) if "--bases" in sys.argv else 8

targets = json.load(open(os.path.join(HERE, "_tw", "targets.json")))
best = defaultdict(list)
import glob
for f in sorted(glob.glob(os.path.join(HERE, "_tw", "vscan_*.json"))):
    d = json.load(open(f))
    for k, v in d["best"].items():
        best[k].extend(tuple(x) for x in v)

_VAR = re.compile(r"SYM_[A-Za-z0-9_]+")

# The SAME deny-list `_diverse_seeds3.py` applies to its inherited templates,
# and for the same measured reason: a base dump's own `concolic_seeds` carry
# `SYM_PARAM_show` (the REQUEST VARIANT, which `VARIANTS` owns), `*_type`
# (DERIVED from SYM_NOTE_TYPE_PROFILE) and identity keys. Replaying them
# verbatim reproduces v3.0's failure — the first rooted drive (TR1) aborted
# the JVM on EVERY seed, 0 paths in 6 variants x 4+ tries.
DENY_SUF = ("_type", "_guid", "_diaspora_handle", "_id", "_person_id",
            "_birthday_year")
DENY_SUB = ("set_rendered_content_type", "_plucked")


def denied(n):
    # SYM_PARAM_show is KEPT (2026-09-10): run_dse.rb:95-101 makes `show` a
    # genuine symbolic request parameter seeded from "" and flipped to
    # "unread" by DSE, and the four `to_ary_notifications_*` statement aliases
    # are exactly {plain,typed} x {unread,not}. Stripping it moved every
    # rooted seed for `notifications_10254800` (typed x unread) onto
    # `notifications_cf379872` (typed x not-unread), so 19 t07 runs drove the
    # WRONG alias. v3.1's blanket SYM_PARAM_* deny was justified by the seed
    # #119 abort, which the 37/37 discovery differential now attributes to
    # `find_by_1_*_not_found` instead.
    if n == "SYM_PARAM_show":
        return False
    return (n.startswith("SYM_PARAM_") or n.endswith(DENY_SUF)
            or any(x in n for x in DENY_SUB))

def wanted_value(expr, side):
    """The seed value that makes `expr` take `side`."""
    body = expr.strip()[1:-1] if expr.startswith("(") else expr
    lhs, op, rhs = body.partition(" == ")
    if rhs == "True":
        return lhs, (side == "taken")
    if rhs == "StringVal('')":
        # the Ruby runtime's native rendering for a string compare
        return lhs, ("" if side == "taken" else "x")
    if rhs == "''":
        # `taken` means the string IS empty; `not_taken` needs a non-empty one.
        return lhs, ("" if side == "taken" else "x")
    raise SystemExit(f"unhandled target shape: {expr}")

# The DISCOVERY ARM (2026-09-10, measured): taking either
# `Core__ClassMethods_find_by_1_not_found` or `..._profile_not_found` sends
# `Person.find_or_fetch_by_identifier` (person.rb:318) into
# `Discovery#fetch_and_save`, which in this environment ABORTS THE JVM in
# libcurl. 37 of 37 toxic seeds in the C32A bulk drive carry one of the two;
# 0 carry neither, against a 25.6 % base rate. So every rooted seed for a
# DIFFERENT target pins both off, or the run dies before it reaches its own
# branch.
DISCOVERY = ("SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found",
             "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_profile_not_found")

per_variant = {}
seen = {}
report = []
for ti, t in enumerate(targets, 1):
    expr, side = t["expr"], t["side"]
    tk = f"t{ti:02d}"
    per_variant[tk] = {v: [] for v in VARIANTS}
    seen[tk] = {v: set() for v in VARIANTS}
    var, val = wanted_value(expr, side)
    other = "taken" if side == "not_taken" else "not_taken"
    made = 0
    for v in VARIANTS:
        bl = sorted(set(best.get(f"{expr}\t{other}\t{v}", [])), reverse=True)[:NB]
        for _npc, p in bl:
            try:
                raw = json.load(open(p))
            except Exception:
                continue
            # VERBATIM (2026-09-10, C8): a ROOTED seed reproduces the base
            # dump's context EXACTLY and flips ONE dimension. The deny-list
            # that used to be applied here was added when the TR1 abort was
            # (wrongly) blamed on `SYM_PARAM_show` and friends; §7.4 traced
            # that abort to the discovery arm instead, and the wall now
            # removes it. Applying the deny-list DROPPED
            # `..._row_person_diaspora_handle`, which `mentionable.rb:35`
            # compares to decide whether the mention resolves to that person
            # at all (Rule G lists `diaspora_handle` as a GATE column) — so
            # the TR6 seeds silently left the mention unresolved and
            # `Person.name_from_attrs` was never called on that chain.
            seeds = dict(raw.get("concolic_seeds") or {})
            d = json.loads(json.dumps(raw))
            amap = canonicalize_ordinals(d)
            inv = defaultdict(list)
            for o, c in amap.items():
                inv[c].append(o)
            keys = [var]
            for c, ords in inv.items():
                if c in var:
                    keys = [var.replace(c, o) for o in ords]
                    break
            for k in keys:
                seeds[k] = val
            key = json.dumps(seeds, sort_keys=True, default=str)
            if key in seen[tk][v]:
                continue
            seen[tk][v].add(key)
            per_variant[tk][v].append(seeds)
            made += 1
    report.append((tk, made, side, var))

import glob as _g
for old in _g.glob(os.path.join(HERE, "_treeR_*.json")):
    os.remove(old)
for tk, pv in per_variant.items():
    for v, lst in pv.items():
        if lst:
            json.dump(lst, open(os.path.join(HERE, f"_treeR_{tk}_{v}.json"), "w"))
for tk, made, side, var in report:
    print(f"  {tk}: {made:3d} seeds  {side:9s} {var}")
