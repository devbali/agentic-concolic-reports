#!/usr/bin/env python3
"""Trim the per-variant one-flip seed files to a TOTAL run budget, keeping the
variants proportional. Pre-registered cap; the trim is printed, never silent."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
BUDGET = int(sys.argv[1]) if len(sys.argv) > 1 else 200
files = {v: os.path.join(HERE, f"_demandR_{v}.json")
         for v in ("auth_html", "anon_html", "auth_json", "anon_json")}
have = {v: (json.load(open(p)) if os.path.exists(p) else []) for v, p in files.items()}
tot = sum(len(x) for x in have.values())
print(f"one-flip seeds: {tot} over {sum(1 for x in have.values() if x)} variants; budget {BUDGET}")
if tot <= BUDGET:
    print("  under budget — nothing trimmed")
    sys.exit(0)
for v, lst in have.items():
    if not lst:
        continue
    keep = max(1, round(BUDGET * len(lst) / tot))
    json.dump(lst[:keep], open(files[v], "w"))
    print(f"  {v}: {len(lst)} -> {keep}")
