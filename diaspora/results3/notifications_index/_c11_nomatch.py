"""The 3 155 cubes whose GATE CONJUNCTION no run walks: say WHICH gate combination
is missing, so the next batch aims at a named thing rather than at "the residue".

For each such cube: find a maximum-size subset of its gates that IS jointly
walked (greedy by how many runs each gate's outcome has), and name the gates
that cannot be added. Report the most common blocking gate-sets."""
import json, os, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals            # noqa: E402

REM = os.environ.get("REM", "_remaining_after.jsonl")
DL = os.environ["DUMP_LIST"]
cubes = [json.loads(l) for l in open(os.path.join(HERE, REM))]
need = set()
for c in cubes:
    need.update(c.get("pre") or {})
print(f"cubes {len(cubes)}; gate expressions {len(need)}", flush=True)

dumps = [l.strip() for l in open(DL) if l.strip()]
pol = {}
t0 = time.time()
for i, fp in enumerate(dumps):
    if i and i % 30000 == 0:
        print(f"   [{i}/{len(dumps)}] {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    b = 1 << i
    canonicalize_ordinals(d)
    seen = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") == "path_condition" and e["expr"] in need:
            seen[e["expr"]].add(bool(e.get("taken")))
    for ex, outs in seen.items():
        for o in outs:
            pol[(ex, o)] = pol.get((ex, o), 0) | b
    del d
print(f"   indexed in {time.time()-t0:.0f}s", flush=True)

blockers = Counter()
sizes = Counter()
for c in cubes:
    pre = sorted((c.get("pre") or {}).items())
    if not pre:
        continue
    m = None
    for g, o in pre:
        mm = pol.get((g, bool(o)), 0)
        m = mm if m is None else (m & mm)
        if not m:
            break
    if m:
        continue                                   # this cube's P IS walked
    # greedy: add gates in order of support, record the first that empties it
    order = sorted(pre, key=lambda t: -bin(pol.get((t[0], bool(t[1])), 0)).count("1"))
    cur = (1 << len(dumps)) - 1
    kept, blocked = [], []
    for g, o in order:
        nxt = cur & pol.get((g, bool(o)), 0)
        if nxt:
            cur = nxt
            kept.append((g, o))
        else:
            blocked.append((g, o))
    sizes[len(blocked)] += 1
    blockers[tuple(sorted(f"{g} :: {'taken' if o else 'not_taken'}" for g, o in blocked))] += 1

print(f"\ncubes whose gate conjunction is NOT walked: {sum(sizes.values())}")
print("how many of their gates cannot be added to a walked prefix:",
      dict(sorted(sizes.items())))
print("\nthe blocking gate-sets, most common first:")
for gs, n in blockers.most_common(12):
    print(f"  {n:5d}  " + " AND ".join(x[-90:] for x in gs))
