#!/usr/bin/env python3
"""Scan the corpus for the tree_missing target expressions.

For each target canonical expression: how many dumps evaluate it, on which
side, in which request variant, and WHICH dumps are the richest exemplars
(most path conditions) — the bases a rooted seed is built on.

usage: DUMP_LIST=... _tree_scan.py [--shards N --shard i] --out f.json
"""
import glob, json, os, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals  # noqa: E402

# run_dse.rb SCENARIOS.
VARIANTS = ("anon_all", "anon_json", "auth_json")

TARGETS = json.load(open(os.path.join(HERE, "_tw", "targets.json")))
# TARGETS: list of {"expr":..., "want": true/false}
TEXPR = {t["expr"] for t in TARGETS}

def opt(name, dflt=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else dflt

_list = os.environ.get("DUMP_LIST")
if _list:
    dumps = sorted(l.strip() for l in open(_list) if l.strip())
    dumps = [d if os.path.isabs(d) else os.path.join(HERE, d) for d in dumps]
else:
    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
NS = int(opt("--shards", "1")); SH = int(opt("--shard", "0"))
dumps = dumps[SH::NS]

stat = defaultdict(Counter)          # expr -> Counter of "side/variant"
best = defaultdict(list)             # (expr, side) -> [(npc, path)]
seen_canon = Counter()
for p in dumps:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), "?")
    try:
        canonicalize_ordinals(d)
    except Exception:
        pass
    evs = d.get("events") or ()
    npc = 0
    hits = {}
    for e in evs:
        if e.get("type") == "path_condition":
            npc += 1
            ex = e.get("expr")
            if ex in TEXPR:
                hits[ex] = bool(e.get("taken"))
    for ex, tk in hits.items():
        side = "taken" if tk else "not_taken"
        stat[ex][side] += 1
        stat[ex][f"{side}@{v}"] += 1
        k = (ex, side, v)
        L = best[k]
        L.append((npc, p))
        if len(L) > 40:
            L.sort(reverse=True); del L[8:]
    del d
out = {"stat": {k: dict(v) for k, v in stat.items()},
       "best": {f"{k[0]}\t{k[1]}\t{k[2]}": sorted(v, reverse=True)[:8] for k, v in best.items()},
       "n": len(dumps)}
json.dump(out, open(opt("--out"), "w"))
print(f"shard {SH}/{NS}: {len(dumps)} dumps scanned")
