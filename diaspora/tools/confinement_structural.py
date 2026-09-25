"""Z3-FREE STRUCTURAL PRICING of confinement — §16b vs §16c strict vs §16c+OR.

    DUMP_LIST=<snapshot> python3 confinement_structural.py <batch_dir> <census.json|-> <ignored> <out.json>

Light loader (raw dumps through the batch's canonicalize_ordinals + fix_len_names,
no Run objects, ~1-2 G on a 100k-profile corpus), the engine's own
`project_confinement` with or_sharing off and on. Structural price = set count,
width histogram, sum(2^width), wide sets — calibrated on posts_show GC0911
where it reproduced the exact census's 1 901 / 6 494 sets and widths exactly.
Left for the endpoint agents (2026-09-11): run when no pass/census is up.

Same universe construction as the census (batch aliases via canonicalize_ordinals,
fix_len_names, untracked filter, declared-independence projection, maximal sets,
foreclosure inference, project_confinement) — but no Z3: parseable = all exprs
(the batch's own passes report UNEVALUABLE=[]), and the price is STRUCTURAL:
set count, width histogram, sum(2^width), sets of width >= 13. Calibration: the
§16c projection is compared to the census JSON's own set count and widths.
"""
import json, os, sys, time
from collections import Counter
B = sys.argv[1]; CENSUS = sys.argv[2]; FORCED = sys.argv[3]
sys.path.insert(0, B); sys.path.insert(0, "/home/dev/project/src")
import coverage_report as CR
from coverage_assumptions import build as build_assumptions
from concolic_engine.assumptions import call_shape, shape_str
from concolic_engine.coverage import (profile_key, maximal_sets, _maximal_cliques,
                                      infer_foreclosures, project_confinement)
t0 = time.time()
files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()]
expr_order, profiles, prof_union, prof_inter = [], {}, [], []
run_outcomes = []
shape_id, side_seen = {}, {}
seen_expr = set()
for n, p in enumerate(files):
    try:
        raw = json.load(open(p)); CR.canonicalize_ordinals(raw); raw = CR.fix_len_names(raw)
    except Exception:
        continue
    outcomes, tr = {}, 0
    for ev in raw.get("events") or ():
        t = ev.get("type")
        if t == "path_condition":
            e = str(ev.get("expr", ""))
            if e not in seen_expr:
                seen_expr.add(e); expr_order.append(e)
            outcomes.setdefault(e, set()).add(bool(ev.get("taken")))
        elif t == "symbolic_call" and ev.get("result_name"):
            sh = call_shape(ev.get("target"), ev.get("note"), ev.get("args"))
            j = shape_id.get(sh)
            if j is None:
                j = shape_id[sh] = len(shape_id)
            tr |= 1 << j
    del raw
    if not outcomes:
        continue
    if tr:
        for e, os_ in outcomes.items():
            k = 2 if len(os_) > 1 else (1 if True in os_ else 0)
            side_seen.setdefault(e, [0, 0, 0])[k] |= tr
    key = profile_key(outcomes); i = profiles.get(key)
    if i is None:
        profiles[key] = len(run_outcomes); run_outcomes.append(outcomes)
        prof_union.append(tr); prof_inter.append(tr)
    else:
        prof_union[i] |= tr; prof_inter[i] &= tr
print(f"loaded {len(files)} dumps -> {len(run_outcomes)} profiles, {len(expr_order)} exprs, {len(shape_id)} shapes {time.time()-t0:.0f}s", flush=True)

class _PC:  # stand-ins for build()
    __slots__ = ("expr",)
    def __init__(self, e): self.expr = e
class _R:
    __slots__ = ("path_conditions",)
    def __init__(self, o): self.path_conditions = [_PC(e) for e in o]
A = build_assumptions([_R(o) for o in run_outcomes])
active = [e for e in expr_order if not A.is_untracked(None, e)]
adj = {e: set() for e in active}
for i, ea in enumerate(active):
    for eb in active[i + 1:]:
        if A.are_independent(None, None, ea, eb):
            continue
        adj[ea].add(eb); adj[eb].add(ea)
aset = set(active)
eval_sets = maximal_sets(frozenset(e for e in o if e in aset) for o in run_outcomes)
projected = []
for s in eval_sets:
    if all(len(adj[v] & s) == len(s) - 1 for v in s):
        projected.append(s); continue
    parts = _maximal_cliques(sorted(s), {v: adj[v] & s for v in s}, cap=16384)
    projected.extend(frozenset(p) for p in parts)
demands16b = maximal_sets(projected)
forecl, bit, _pm = infer_foreclosures(active, run_outcomes)
by_gate = {}
for (g, o), fm in forecl.items():
    by_gate.setdefault(g, []).append((o, fm))
print(f"active={len(active)} eval sets={len(eval_sets)} -> §16b demand sets={len(demands16b)} "
      f"foreclosures={sum(bin(m).count('1') for m in forecl.values())} {time.time()-t0:.0f}s", flush=True)

def price(sets, tag):
    w = Counter(len(s) for s in sets)
    s2 = sum(2 ** len(s) for s in sets)
    wide = [s for s in sets if len(s) >= 13]
    print(f"{tag}: sets={len(sets)} sum(2^w)={s2:.3e} max_w={max(w) if w else 0} "
          f"wide(>=13)={len(wide)} wide_mass={sum(2**len(s) for s in wide):.3e} "
          f"widths(top)={', '.join(f'{k}x{v}' for k, v in w.most_common(8))}", flush=True)
    return s2

C = json.load(open(CENSUS))["census"] if CENSUS != "-" else None
if C:
    print(f"census JSON: 16b sets={C['16b']['cliques']} sat={float(C['16b']['satisfiable']):.3e}; "
          f"16c sets={C['16c']['cliques']} sat={float(C['16c']['satisfiable']):.3e}")
price(demands16b, "§16b (structural)")
pj = project_confinement(active, expr_order, run_outcomes, prof_union, prof_inter, side_seen,
                         demands16b, by_gate, bit, 16384, or_sharing=False)
print(f"§16c STRICT: decided={len(pj['footprint'])} coeval={len(pj['coevaluated'])} disq={len(pj['disqualified'])} "
      f"pairs confined={len(pj['confined'])} overlapping={len(pj['overlapping'])} disq_pairs={len(pj['disq_pairs'])} undecidable={len(pj['undecidable'])}")
p16c = price(pj["demands"], "§16c strict (structural)")
pj2 = project_confinement(active, expr_order, run_outcomes, prof_union, prof_inter, side_seen,
                          demands16b, by_gate, bit, 16384)
print(f"§16c+OR (engine licence): pairs confined={len(pj2['confined'])} of which OR-licensed={len(pj2['or_pairs'])}; "
      f"refused by the 2x2={len(pj2['and_pairs'])}")
from collections import Counter as _C
print("  refused by class:", dict(_C(x[3] for x in pj2["and_pairs"])))
por = price(pj2["demands"], "§16c+OR (structural)")
print(f"RATIO §16c-strict/§16c+OR on sum(2^w): {p16c/max(por,1):.1f}x")
wide = [s_ for s_ in pj2["demands"] if len(s_) >= 13]
glue = Counter()
for s_ in wide:
    m = sorted(s_)
    for i, a in enumerate(m):
        for b in m[i+1:]:
            pr = (a, b) if a < b else (b, a)
            if pr not in pj2["confined"]:
                glue[pr] += 1
print(f"wide parts after OR: {len(wide)}; non-confined pairs inside them: {len(glue)}; top:")
for (a, b), n in glue.most_common(10):
    print(f"  {n:4d} sets  {a[:60]}  x  {b[:60]}")
print("top AND/non-monotone refusals:")
for a, b, j, cls, cell, pi in pj2["and_pairs"][:10]:
    print(f"  {cls:<20} {a[:50]} x {b[:50]}")
json.dump({"16b_sets": len(demands16b), "16c_sets": len(pj["demands"]), "16c_or_sets": len(pj2["demands"]),
           "sum2w": {"16b": sum(2**len(x) for x in demands16b), "16c": sum(2**len(x) for x in pj["demands"]),
                     "16c_or": sum(2**len(x) for x in pj2["demands"])},
           "pairs_strict": {"confined": len(pj["confined"]), "disq": len(pj["disq_pairs"]), "undecidable": len(pj["undecidable"])},
           "pairs_or": {"confined": len(pj2["confined"]), "or_licensed": len(pj2["or_pairs"]),
                        "refused": dict(_C(x[3] for x in pj2["and_pairs"]))},
           "wide_glue": [[a, b, n] for (a, b), n in glue.most_common(200)],
           "widths_16c_or": Counter(len(x) for x in pj2["demands"]),
           "widths_16c": Counter(len(x) for x in pj["demands"])},
          open(sys.argv[4], "w"), default=dict)
print(f"DONE {time.time()-t0:.0f}s")
