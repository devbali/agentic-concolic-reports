#!/usr/bin/env python3
"""WIDE rooted seeds — EVERY DISTINCT base seed dict that reaches the site.

people_stream's TR0910w round, ported. `_tree_root.py` takes the 8 richest
bases per (target, side, variant); that is the cheap first attempt. Before an
unreachable side may be DECLARED, the brief requires driving at it from every
base that reaches the site — so this tool scans the whole snapshot, keeps every
dump that EVALUATES the target on the other side, dedupes by the base's own
`concolic_seeds` dict, and emits one rooted seed per distinct dict: verbatim
base + the single flip (§5), with `len()` seed keys (§6).

usage: DUMP_LIST=<snapshot> _tree_root_wide.py --targets t01,t02 [--cap N]
writes _treeW_<tk>_<variant>.json
"""
import glob, json, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals, fix_len_names  # noqa: E402

# `_tree_root.py` is a SCRIPT, not a module: importing it re-runs the whole
# rooted-seed build (and deletes/rewrites `_treeR_*.json`). Its two pure
# helpers are therefore loaded by exec'ing only their definitions, so this tool
# uses the SAME code without the side effect.
_src = open(os.path.join(HERE, "_tree_root.py")).read()
_ns = {"re": re, "sys": sys}
for _fn in ("def wanted_value", "def _seed_key"):
    _i = _src.index(_fn)
    _j = _src.index("\n\n\n", _i)
    exec(compile(_src[_i:_j], "_tree_root.py", "exec"), _ns)
wanted_value, _seed_key = _ns["wanted_value"], _ns["_seed_key"]

VARIANTS = ("auth_html", "anon_html", "auth_json", "anon_json")


def opt(name, dflt=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else dflt


CAP = int(opt("--cap", "400"))
targets = json.load(open(os.path.join(HERE, "_tw", "targets.json")))
want = (opt("--targets") or "").split(",")
want = [w.strip() for w in want if w.strip()]
sel = {f"t{i:02d}": t for i, t in enumerate(targets, 1)
       if not want or f"t{i:02d}" in want}
print("targets:", sorted(sel))

_list = os.environ.get("DUMP_LIST")
if _list:
    dumps = sorted(l.strip() for l in open(_list) if l.strip())
    # A RELATIVE snapshot path resolves against the PROCESS cwd, which is not
    # this batch — the first run of this tool silently read
    # notifications_index's dumps and reported 0 bases for every target.
    # `_prune_corpus.py` / `_tree_root.py` already join against HERE; so does
    # this now.
    dumps = [d if os.path.isabs(d) else os.path.join(HERE, d) for d in dumps]
else:
    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
print(f"snapshot: {len(dumps)} dumps")

out = {tk: defaultdict(dict) for tk in sel}     # tk -> variant -> digest -> seeds
reach = {tk: 0 for tk in sel}
for p in dumps:
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), None)
    if v is None:
        continue
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    seeds0 = raw.get("concolic_seeds")
    if not seeds0:
        continue
    d = json.loads(json.dumps(raw))
    amap = canonicalize_ordinals(d)
    d = fix_len_names(d)
    got = {}
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            got.setdefault(e["expr"], set()).add(bool(e.get("taken")))
    inv = defaultdict(list)
    for o, c in amap.items():
        inv[c].append(o)
    for tk, t in sel.items():
        expr, side = t["expr"], t["side"]
        sides = got.get(expr)
        if not sides:
            continue
        # a base is USEFUL only if it evaluated the target on the OTHER side
        if (side == "taken") in sides:
            continue
        reach[tk] += 1
        if len(out[tk][v]) >= CAP:
            continue
        var, val = wanted_value(expr, side)
        keys = [var]
        for c, ords in inv.items():
            if c in var:
                keys = [var.replace(c, o) for o in ords]
                break
        seeds = dict(seeds0)                      # VERBATIM base (§5)
        for k in keys:
            seeds[_seed_key(k)] = val             # len() translation (§6)
        out[tk][v][json.dumps(seeds, sort_keys=True, default=str)] = seeds

for old in glob.glob(os.path.join(HERE, "_treeW_*.json")):
    os.remove(old)
for tk in sorted(out):
    tot = 0
    for v, by in out[tk].items():
        if by:
            json.dump(list(by.values()),
                      open(os.path.join(HERE, f"_treeW_{tk}_{v}.json"), "w"))
            tot += len(by)
    print(f"  {tk}: {reach[tk]:6d} bases reach the site -> {tot:5d} DISTINCT rooted seeds "
          f"({', '.join(f'{v}:{len(b)}' for v, b in sorted(out[tk].items()) if b)})")
