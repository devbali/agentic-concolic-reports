#!/usr/bin/env python3
"""Book a round the four ways §78.5 requires, off two checkpoints:
   closed (a set that had a gap and is clean again), gone (set merged away),
   surviving, new. usage: _p18_book.py <prev.ckpt> <new.ckpt> [runs]"""
import json, sys
def load(p):
    f = open(p); f.readline(); out = {}
    for l in f:
        r = json.loads(l); out[r["k"]] = bool(r["v"].get("combos"))
    return out
a, b = load(sys.argv[1]), load(sys.argv[2])
runs = int(sys.argv[3]) if len(sys.argv) > 3 else 0
ga = {k for k, v in a.items() if v}; gb = {k for k, v in b.items() if v}
closed = {k for k in ga if k in b and not b[k]}
gone = ga - set(b)
surv = ga & gb
new = gb - set(a)
broke = {k for k in b if b[k] and k in a and not a[k]}
print(f"  demand sets   {len(a)} -> {len(b)}")
print(f"  sets with gap {len(ga)} -> {len(gb)}   delta {len(gb)-len(ga)}")
print(f"  closed (clean again) {len(closed)}   gone (merged away) {len(gone)}"
      f"   surviving {len(surv)}   new {len(new)}   newly broken {len(broke)}")
if runs:
    print(f"  rate = {(len(ga)-len(gb))/runs:+.3f} per run over {runs} runs")
