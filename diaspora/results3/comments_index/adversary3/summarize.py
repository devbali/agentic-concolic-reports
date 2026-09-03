#!/usr/bin/env python3
"""Adversary round 3 helper: per real run, the depth-0 target calls and the real
SQL statements grouped by the target frame that issued them. Read-only."""
import json, sys, re, collections

def norm(s):
    s = re.sub(r'\s+', ' ', s.strip())
    return s

for path in sys.argv[1:]:
    data = json.load(open(path))
    print("=" * 100)
    print(path)
    for sc in data:
        if sc["name"] == "_cumulative_coverage":
            continue
        print(f"-- scenario {sc['name']}  error={sc.get('error')}")
        d0 = collections.Counter()
        alld = collections.Counter()
        for c in sc["target_calls"]:
            alld[(c["target"], c["depth"])] += 1
            if c["depth"] == 0:
                d0[c["target"]] += 1
        print("   depth-0 target calls:")
        for t, n in sorted(d0.items()):
            print(f"      {n:4d}  {t}")
        deeper = {k: v for k, v in alld.items() if k[1] > 0}
        if deeper:
            print("   nested (depth>0) target calls:")
            for (t, dep), n in sorted(deeper.items()):
                print(f"      {n:4d}  d{dep} {t}")
        byframe = collections.Counter()
        for st in sc.get("statements", []):
            byframe[(st.get("under"), norm(st["sql"]))] += 1
        print(f"   real statements ({sum(byframe.values())} total, {len(byframe)} distinct):")
        for (frame, sql), n in sorted(byframe.items(), key=lambda x: (str(x[0][0]), x[0][1])):
            print(f"      {n:4d}  [{frame}]")
            print(f"            {sql[:230]}")
