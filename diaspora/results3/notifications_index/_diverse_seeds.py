#!/usr/bin/env python3
"""Bulk DIVERSE seeds (2026-09-09).

Why this exists: the demand loop pins ONE exact assignment per clique per
round, but a clique only leaves MISSING when ALL its satisfiable assignments
are observed. With 1 671 cliques of 5-14 seedable variables that is ~1.5M
targeted runs — 13 h of pure run time — and raising MAX_MISSING_PER_CLIQUE to
name more targets makes the coverage pass cost tens of hours.

The leverage: every one of these variables is an INPUT (`seed_for(var,
default)` in concolic_targets.rb, verified: 181/181 seeded lengths held), and
ONE run assigns all of them at once — so a single varied run covers one
assignment in EVERY clique simultaneously. Coupon-collector says ~n*ln(n)
varied runs cover a clique of n assignments, and they cover all cliques in
parallel. That is ~80 min instead of 13 h.

Seeds are built from REAL dumps' `concolic_seeds` (so every key is a valid
runtime key in the right ordinal form) with the seedable values randomised
over their declared domains (apply_len_bounds: lists {0,1}, the paginated
to_ary {0,1,3}, preloaded actors {0,1,4}).

Usage: python3 _diverse_seeds.py [N] [out.json]
"""
import glob, json, os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
N = int(sys.argv[1]) if len(sys.argv) > 1 else 4000
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "_diverseR.json")
random.seed()

# DOMAIN MUST COVER EVERY THRESHOLD THE PCs ACTUALLY TEST (2026-09-09).
# Measured over the missing set: `len > 1` appears 8 021 times, `== 0` 392,
# `!= 0` 88, `> 3` 56, `> 0` 24. A domain of {0,1} makes the DOMINANT demand
# (`> 1`) unsatisfiable by construction — the first version of this file had
# exactly that bug. {0,1,2,4} satisfies every threshold above and both sides
# of each: 0 gives `==0`/`not >0`; 1 gives `>0`/`not >1`; 2 gives `>1`/`not
# >3`; 4 gives `>3`.
def dom(key):
    return (0, 1, 2, 4)

templates = []
for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json")))[::37]:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    s = d.get("concolic_seeds") or {}
    if s:
        templates.append(s)
if not templates:
    print("no seed-bearing dumps"); sys.exit(1)
print(f"{len(templates)} seed templates")

out, seen = [], set()
for _ in range(N * 3):
    if len(out) >= N:
        break
    t = dict(random.choice(templates))
    for k in list(t):
        if k.startswith("len("):
            t[k] = random.choice(dom(k))
        elif isinstance(t[k], bool):
            t[k] = random.random() < 0.5
        elif k.startswith("SYM_NOTE_TYPE_PROFILE"):
            t[k] = random.randint(0, 7)
    key = json.dumps(t, sort_keys=True)
    if key in seen:
        continue
    seen.add(key)
    out.append(t)
json.dump(out, open(OUT, "w"))
print(f"wrote {len(out)} diverse seeds -> {OUT}")
