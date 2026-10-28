#!/usr/bin/env python3
"""C14 — turn the exact enumerator's EMIT_REMAINING stream into a gaps file.

The C12/C13 rounds took ONE witness per demand set (the checker's cap), so a
round could close at most one leaf per set. This consumes EVERY remaining
satisfiable assignment the enumerator emits, grouped by LEAF GROUP
(set x gate prefix `pre`) — which is the granularity at which a base can be
gate-matched, since different leaf groups of one set pin different gates.

record: {id, set, group, width, pre, cube[[expr,outcome]], reachable, model{}}
`model` is empty by design: the enumerator proved satisfiability, and the
constructor's resolver prefers OBSERVED corpus values over a model value
anyway (§25.3 rule 4), so there is nothing a model would add here.
"""
import json, os, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.environ.get("C14_REMAIN", os.path.join(HERE, "_c14_remaining.jsonl"))
OUT = os.environ.get("C14_GAPS", os.path.join(HERE, "_c14_gaps.json"))

gaps, groups, bad = [], {}, 0
per_set = Counter(); per_group = Counter(); widths = Counter()
reach = Counter()
for line in open(SRC):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
    except Exception:
        bad += 1
        continue
    pre = r["pre"]; asg = r["asg"]
    gkey = (r["set"], tuple(sorted(pre.items())))
    gid = groups.setdefault(gkey, len(groups))
    cube = sorted(set(list(pre.items()) + list(asg.items())))
    gaps.append({
        "id": f"c{len(gaps):06d}",
        "set": r["set"], "group": gid, "set_capped": False,
        "width": len(cube), "surv": r.get("surv"),
        "reachable": bool(r.get("reachable")),
        "pre": pre,
        "cube": [[e, bool(o)] for e, o in cube],
        "model": {},
    })
    per_set[r["set"]] += 1
    per_group[gid] += 1
    widths[len(cube)] += 1
    reach["reachable" if r.get("reachable") else "unreachable"] += 1

print(f"remaining cubes      : {len(gaps)}   (unparsed lines {bad})")
print(f"demand sets involved : {len(per_set)}")
print(f"leaf groups involved : {len(groups)}")
print(f"reachability         : {dict(reach)}")
print("cubes per SET   distribution: " + ", ".join(
    f"{k}:{v}" for k, v in sorted(Counter(per_set.values()).items())[:16]))
print(f"  top sets: {[c for _s, c in per_set.most_common(8)]}")
print("cubes per GROUP distribution: " + ", ".join(
    f"{k}:{v}" for k, v in sorted(Counter(per_group.values()).items())[:16]))
print("width histogram : " + ", ".join(f"{k}:{v}" for k, v in sorted(widths.items())))
ex = Counter(e for g in gaps for e, _ in g["cube"])
print(f"distinct expressions over all cubes: {len(ex)}")
json.dump(gaps, open(OUT, "w"))
print(f"C14-GAPS-DONE {OUT} ({os.path.getsize(OUT)/1e6:.1f} MB)")
