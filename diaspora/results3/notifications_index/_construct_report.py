#!/usr/bin/env python3
"""Per-GATE-COMBINATION verdict for a direct-construction replay.

"No run produced this combination" is not "the program cannot". This classifies
each constructed combination by what its own replay did:

  REALISED      some run evaluated EVERY demanded decision with the demanded
                outcome — the combination is producible, full stop.
  UNEVALUATED   every run left at least one demanded decision unevaluated (the
                walk never reached it): not evidence of impossibility.
  CONTRADICTED  a demanded decision was EVALUATED and took the OTHER outcome in
                every run despite being seeded — the only shape that is
                impossibility evidence, and the gate is named.

usage: PLAN=_construct_CT2_plan.json python3 -u _construct_report.py 'dump_*CT2*.json'
"""
import glob, json, os, re, sys
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals  # noqa: E402

_UNLEN = re.compile(r"len\(([^()]+)\)")
PAT = sys.argv[1] if len(sys.argv) > 1 else "dump_*CT2*.json"
plan = json.load(open(os.environ.get("PLAN", os.path.join(HERE, "_construct_CT2_plan.json"))))

demanded = {}          # combo -> {expr: want}
for p in plan:
    if p.get("status") == "CONSTRUCTED":
        demanded.setdefault(p["combo"], {}).update(p["demanded"])
print(f"plan: {len(demanded)} constructed gate combinations")

files = sorted(glob.glob(os.path.join(HERE, PAT)))
print(f"replay dumps: {len(files)}")

hit = defaultdict(lambda: defaultdict(int))    # combo -> expr -> runs with demanded outcome
opp = defaultdict(lambda: defaultdict(int))    # combo -> expr -> runs with the OTHER outcome
seen_runs = Counter()
full_real = Counter()
for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    combo = (d.get("concolic_seeds") or {}).get("__ctcombo__")
    if combo is None or combo not in demanded:
        continue
    seen_runs[combo] += 1
    canonicalize_ordinals(d)
    pcs = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            ex = e["expr"]
            pcs[ex].add(bool(e.get("taken")))
            ex2 = _UNLEN.sub(r"SYM_LEN_\1", ex)
            if ex2 != ex:
                pcs[ex2].add(bool(e.get("taken")))
    ok = True
    for ex, want in demanded[combo].items():
        if ex not in pcs:
            ok = False
            continue
        if want in pcs[ex]:
            hit[combo][ex] += 1
        else:
            opp[combo][ex] += 1
            ok = False
    if ok:
        full_real[combo] += 1

verdict = {}
contradicted_exprs = Counter()
for c, dem in demanded.items():
    if full_real[c]:
        verdict[c] = "REALISED"
        continue
    bad_opp = [e for e in dem if opp[c].get(e) and not hit[c].get(e)]
    if bad_opp:
        verdict[c] = "CONTRADICTED"
        for e in bad_opp:
            contradicted_exprs[e] += 1
    else:
        verdict[c] = "UNEVALUATED"
vc = Counter(verdict.values())
print("\n=== PER-COMBINATION VERDICT ===")
for k in ("REALISED", "UNEVALUATED", "CONTRADICTED"):
    print(f"  {k:13s} {vc.get(k,0):4d} of {len(demanded)}"
          f"   ({100.0*vc.get(k,0)/max(1,len(demanded)):.1f} %)")
print(f"  runs replayed: {sum(seen_runs.values())}, "
      f"fully realising runs: {sum(full_real.values())}")
if contradicted_exprs:
    print("\n  DECISIONS THAT FLIPPED BACK DESPITE THEIR SEED "
          "(the only impossibility evidence):")
    for e, n in contradicted_exprs.most_common(12):
        print(f"    {n:4d} combinations  {e[:110]}")
else:
    print("\n  NO decision flipped back despite its seed — nothing here is "
          "evidence of impossibility.")
json.dump({"combinations": len(demanded), "verdict": dict(vc),
           "runs": sum(seen_runs.values()),
           "contradicted": contradicted_exprs.most_common(50),
           "per_combo": {str(c): verdict[c] for c in verdict}},
          open(os.path.join(HERE, "_construct_report.json"), "w"), indent=1)
print("\nwrote _construct_report.json")
