#!/usr/bin/env python3
"""VERIFY the 768 before calling them residue (coordinator, 2026-09-11).

`_exact_enum.py` marks a leaf group `reachable` only when some run's PROFILE
MASK equals the group's survivor mask exactly AND its outcomes agree with the
group's gate assignment `pre`. That is narrower than "the corpus produced this
gate combination": a run that walked the gates but evaluated a DIFFERENT
(e.g. larger or smaller) survivor set does not count. On notifications the same
classification was partly wrong for exactly this reason.

Two checks, both on the FULL corpus, not the pruned list:

  (a) §13.1 COMPATIBILITY — for each distinct gate combination `pre` among the
      remaining assignments, does ANY run evaluate every gate in `pre` with the
      demanded outcome? If yes, the cubes under it are DRIVING BACKLOG (a base
      exists; the seeder simply was not given it), not residue.
  (b) TWO KEYS OR ONE VALUE, TWO NAMES — for the gate pairs that make a group
      'impossible', are the two decisions seeded independently (two honoured
      seed keys in the same run) or are they two names for one runtime value?

usage: _x7_verify768.py <remaining.jsonl> [DUMP_LIST]
"""
import glob, json, os, sys
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
import coverage_report as CR  # noqa: E402

REM = sys.argv[1]
DL = os.environ.get("DUMP_LIST")
files = ([l.strip() for l in open(DL) if l.strip()] if DL
         else sorted(glob.glob(os.path.join(HERE, "dump_*.json"))))
print(f"corpus: {len(files)} dumps")

rows = [json.loads(l) for l in open(REM)]
print(f"remaining assignments: {len(rows)}  (reachable={sum(1 for r in rows if r.get('reachable'))})")

pres = defaultdict(int)
for r in rows:
    pres[tuple(sorted((r.get("pre") or {}).items()))] += 1
print(f"distinct gate combinations among them: {len(pres)}")

wanted = set()
for p in pres:
    for e, _ in p:
        wanted.add(e)
print(f"gate expressions involved: {len(wanted)}")

# one pass over the corpus: per run, the outcome of every wanted gate, plus the
# seed keys it honoured
run_out = []
seed_keys = []
for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    CR.canonicalize_ordinals(d)
    o = {}
    for ev in d.get("events") or ():
        if ev.get("type") == "path_condition" and ev["expr"] in wanted:
            o.setdefault(ev["expr"], set()).add(bool(ev.get("taken")))
    run_out.append(o)
    seed_keys.append(set((d.get("concolic_seeds") or {}).keys()))
print(f"indexed {len(run_out)} runs")

producers = Counter()
backlog = 0
residue = 0
for p, n in pres.items():
    hit = 0
    for o in run_out:
        ok = True
        for e, v in p:
            s = o.get(e)
            if s is None or v not in s:
                ok = False
                break
        if ok:
            hit += 1
            if hit >= 3:
                break
    producers[p] = hit
    if hit:
        backlog += n
    else:
        residue += n

print()
print("=== (a) §13.1 COMPATIBILITY ON THE FULL CORPUS ===")
print(f"  gate combinations WITH a producing run : {sum(1 for v in producers.values() if v)} "
      f"of {len(pres)}  -> {backlog} assignments are DRIVING BACKLOG")
print(f"  gate combinations with NO producing run: {sum(1 for v in producers.values() if not v)} "
      f"of {len(pres)}  -> {residue} assignments are RESIDUE")
print()
for p, n in sorted(pres.items(), key=lambda kv: -kv[1])[:6]:
    print(f"  [{n:5d} assignments, producers={producers[p]}]")
    for e, v in p:
        print(f"      {str(v):5s}  {e[:96]}")
    print()

print("=== (b) TWO HONOURED SEED KEYS, OR ONE VALUE WITH TWO NAMES? ===")
for p in list(pres)[:1]:
    ex = [e for e, _ in p]
for e in sorted(wanted):
    base = e.strip("()").split(" ")[0]
    seeded = sum(1 for sk in seed_keys if any(k == base or k.startswith(base) for k in sk))
    evald = sum(1 for o in run_out if e in o)
    print(f"  seeded_in={seeded:5d}  evaluated_in={evald:5d}  {e[:92]}")
