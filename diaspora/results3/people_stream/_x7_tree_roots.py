#!/usr/bin/env python3
"""Generic ROOTED seeds for whatever `coverage_summary.json` reports as
tree_missing, built the way _tree_root.py / _demand_root.py build theirs: a
REAL DUMP'S OWN SEEDS (from a run that provably evaluated the expression, on
the OTHER side) with EXACTLY the target dimension moved.

Canonical -> ordinal comes from the BASE DUMP'S OWN alias map and EVERY ordinal
backing the canonical is seeded (the map is many-to-one by design; picking one
contradicts the demand whenever the path takes another — _demand_root.py's
2026-09-09 fix, same defect).

writes _x7_tree_roots.json
"""
import glob, json, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals  # noqa: E402

NB = int(sys.argv[sys.argv.index("--bases") + 1]) if "--bases" in sys.argv else 30
summary = json.load(open(os.path.join(HERE, "coverage_summary.json")))
tm = summary.get("tree_missing") or []
targets = []
for entry in tm:
    # entries are [expr, "taken"|"not_taken"] or "expr :: taken"
    if isinstance(entry, (list, tuple)):
        expr, side = entry[0], entry[1]
    else:
        expr, _, side = str(entry).rpartition("::")
        expr, side = expr.strip(), side.strip()
    targets.append((expr, side == "taken"))
print("tree_missing targets: %d" % len(targets))
for e, w in targets:
    print("   want %-9s %s" % ("taken" if w else "not_taken", e[:100]))

_VAR = re.compile(r"\(([A-Za-z0-9_]+)\s*(==|!=|<|<=|>|>=)\s*(.*)\)\s*$", re.S)

def wanted_seed(expr, want_taken):
    """The seed that makes `expr` evaluate to `want_taken`. Only var-vs-literal
    compares are seedable — a VAR==VAR compare is moved by its LEFT var, which
    is what _x7_identity_roots.py does for the identity pair."""
    m = _VAR.match(expr.strip())
    if not m:
        return None
    var, op, lit = m.group(1), m.group(2), m.group(3).strip()
    lm = re.match(r"\A(?:StringVal|IntVal|BoolVal)\((.*)\)\Z", lit, re.S)
    if lm:
        lit = lm.group(1).strip()
    if lit in ("True", "true"):
        val = True
    elif lit in ("False", "false"):
        val = False
    elif lit.startswith("'") and lit.endswith("'"):
        val = lit[1:-1]
    elif re.fullmatch(r"-?\d+", lit):
        val = int(lit)
    else:
        return None
    if op == "==":
        if want_taken:
            return var, val
        # the other side: any different value
        if isinstance(val, bool):  return var, (not val)
        if isinstance(val, int):   return var, val + 424242
        return var, (val + "_x7other") if isinstance(val, str) else None
    if op == "!=":
        if not want_taken:
            return var, val
        if isinstance(val, bool):  return var, (not val)
        if isinstance(val, int):   return var, val + 424242
        return var, (val + "_x7other") if isinstance(val, str) else None
    return None

roots, seen = [], set()
files = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
for expr, want in targets:
    plan = wanted_seed(expr, want)
    if plan is None:
        print("   SKIP (not a var-vs-literal compare, needs a hand-built root): %s" % expr[:90])
        continue
    canon_var, value = plan
    picked = 0
    nev = [0]
    for p in files:
        if picked >= NB:
            break
        try:
            d = json.load(open(p))
        except Exception:
            continue
        seeds = d.get("concolic_seeds") or {}
        if not seeds:
            continue
        amap = canonicalize_ordinals(d)
        inv = defaultdict(list)
        for o, c in amap.items():
            inv[c].append(o)
        # the dump must have EVALUATED this expression (on either side): that is
        # what makes its seeds a CONTEXT that reaches the site
        evaluated = any(e.get("type") == "path_condition" and e["expr"] == expr
                        for e in (d.get("events") or ()))
        if not evaluated:
            continue
        nev[0] += 1
        # canon_var is a COLUMN of a canonicalised RESULT
        # (`…_records_posts_915a4835` + `_row_text`); the alias map is keyed by
        # the RESULT name only, so match the longest canonical result that is a
        # prefix and re-append the column suffix to every ordinal backing it.
        ords = []
        for o, c in amap.items():
            if canon_var.startswith(c):
                ords.append(o + canon_var[len(c):])
        if not ords and canon_var in seeds:
            ords = [canon_var]
        if not ords:
            continue
        root = dict(seeds)
        for o in ords:
            root[o] = value
        key = json.dumps(root, sort_keys=True)
        if key in seen:
            continue
        seen.add(key)
        roots.append(root)
        picked += 1
    print("   %-9s %-80s evaluating-dumps=%d roots=%d" % ("taken" if want else "not_taken", expr[:80], nev[0], picked))

out = os.path.join(HERE, "_x7_tree_roots.json")
json.dump(roots, open(out, "w"))
print("-> %d rooted seeds -> %s" % (len(roots), out))
