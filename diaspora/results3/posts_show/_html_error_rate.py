#!/usr/bin/env python3
"""§76 — the html arm's ERROR RATE on the CURRENT corpus, pre- and post-repair.

The 2026-09-10 21:00 render repair (§46) is the boundary (`targets.rb`'s own
mtime). Stride sample, both sides, both html scenarios, per terminal kind:
an APPLICATION terminal (RecordNotFound / NonPublic) is the app's own arm; a
RIG terminal (ActionView::Template::Error, NotImplementedError) is this
framework failing to run the app and it is the one that matters for class (c).
"""
import glob, json, os, sys
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
STRIDE = int(os.environ.get("STRIDE", "20"))
BOUND = os.path.getmtime(os.path.join(HERE, "targets.rb"))
RIG = ("ActionView::Template::Error", "NotImplementedError", "NoMethodError",
       "NameError", "TypeError", "ArgumentError", "SystemStackError")
tot = Counter(); kinds = {"pre": Counter(), "post": Counter()}
for v in ("auth_html", "anon_html", "auth_json", "anon_json"):
    files = sorted(glob.glob(os.path.join(HERE, f"dump_{v}*.json")))[::STRIDE]
    for fp in files:
        side = "post" if os.path.getmtime(fp) >= BOUND else "pre"
        tot[(v, side)] += 1
        try:
            d = json.load(open(fp))
        except Exception:
            kinds[side]["UNPARSEABLE"] += 1
            continue
        e = d.get("error")
        k = (e.get("type") if isinstance(e, dict) else e) if e else None
        kinds[side][k or "(none — ran to the end)"] += 1
        tot[(v, side, "rig")] += 1 if (k in RIG) else 0
        del d
print(f"boundary = targets.rb mtime {BOUND:.0f}; stride {STRIDE}")
print("\nsampled dumps per scenario/side:")
for (k, v_) in sorted((k for k in tot if len(k) == 2)):
    print(f"  {k:<10} {v_:<5} {tot[(k, v_)]:>6}  rig terminals {tot[(k, v_, 'rig')]:>6}")
for side in ("pre", "post"):
    n = sum(v for k, v in kinds[side].items())
    print(f"\n=== {side.upper()}-REPAIR terminals ({n} sampled) ===")
    for k, v in kinds[side].most_common(12):
        print(f"  {v:>7}  {100.0*v/max(1,n):5.1f} %  {k}")
print("\nHTML ERROR RATE DONE")
