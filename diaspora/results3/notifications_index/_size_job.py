#!/usr/bin/env python3
"""SIZE THE JOB (2026-09-09): the real distance to `missing == 0`.

At MMC=1 `missing` shows ONE unobserved satisfiable outcome-assignment per
clique; the distance is the number of satisfiable assignments per clique
NOT YET observed by a run that evaluated the whole clique. This script
computes it locally, faithfully to coverage.py step 6:
  * clique = the expression set of a missing[] entry (MMC=1: 1 entry/clique);
  * satisfiable assignments = Z3 enumeration over the clique's expressions
    under the engine's merged declarations + apply_len_bounds bounds (the
    batch declares no SymbolicConstraintAssumption) — blocking-clause loop,
    capped at CAP per clique;
  * observed = for every dump, THROUGH THE ENGINE'S LOAD PATH
    (canonicalize_ordinals -> fix_len_names -> Run.from_dict ->
    apply_len_bounds), the outcome family of each clique the run evaluated
    entirely (an expr seen both ways in one run covers both outcomes —
    coverage.py's blocking-clause semantics);
  * attribution by dump group (base corpus / D-round targeted / DIV1 v1 /
    PV pilot / DV* v2 diverse) so each seeding strategy's contribution is
    measured, not assumed.
Env: DUMP_LIMIT=N (smoke), CAP (default 4096), OUT (json path).
"""
import json, os, re, sys, time, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals, fix_len_names, apply_len_bounds
from concolic_engine.run import Run
from concolic_engine.solver import check_satisfiability, _Z3_NAMESPACE
import z3
import logging; logging.getLogger("concolic_engine.solver").setLevel(logging.ERROR)

CAP = int(os.environ.get("CAP", "4096"))
LIMIT = int(os.environ.get("DUMP_LIMIT", "0"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_size_job.json"))
t0 = time.time()

def conjuncts(nc):
    out = []
    for part in nc.split(" AND "):
        part = part.strip(); want = True
        m = re.match(r"^Not\((.*)\)$", part, re.S)
        if m: part, want = m.group(1).strip(), False
        out.append((part, want))
    return out

missing = [m for m in json.load(open(os.path.join(HERE, "coverage_summary.json")))["missing"] if not m.get("untracked")]
cliques = []           # list of (exprs tuple, witness tuple of bools)
for m in missing:
    cj = conjuncts(m["node_constraint"])
    cliques.append((tuple(e for e, _ in cj), tuple(w for _, w in cj)))
print(f"{len(cliques)} cliques (blocking witnesses)", flush=True)
by_expr = collections.defaultdict(list)
for i, (ex, _) in enumerate(cliques):
    for e in ex: by_expr[e].append(i)

def group_of(fn):
    if "_DV" in fn: return "DV_v2"
    if "_PV" in fn: return "PV_pilot"
    if "_DIV1" in fn: return "DIV1_v1"
    if re.search(r"_D\d+[a-z]{3}\.json$", fn): return "D_targeted"
    if re.search(r"_C\d", fn): return "C_probe"
    return "base"

files = sorted(f for f in os.listdir(HERE) if f.startswith("dump_") and f.endswith(".json"))
if LIMIT: 
    import random; random.seed(7); files = sorted(random.sample(files, min(LIMIT, len(files))))
print(f"scanning {len(files)} dumps", flush=True)
decls, bounds = {}, {}
fam = [collections.defaultdict(set) for _ in cliques]   # clique -> group -> set(family tuples)
evaluated_runs = [0] * len(cliques)
ngroup = collections.Counter(); bad = 0
for k, fn in enumerate(files):
    try:
        raw = json.load(open(os.path.join(HERE, fn)))
        canonicalize_ordinals(raw)
        run = apply_len_bounds(Run.from_dict(fix_len_names(raw)))
    except Exception as e:
        bad += 1; continue
    g = group_of(fn); ngroup[g] += 1
    for sv, d in zip(run.symbolic_vars, run.z3_declarations()):
        decls.setdefault(sv.name, d)
        if sv.low is not None and sv.high is not None: bounds.setdefault(sv.name, (sv.low, sv.high))
    oc = {}
    for pc in run.path_conditions: oc.setdefault(pc.expr, set()).add(bool(pc.taken))
    cand = set()
    for e in oc:
        cand.update(by_expr.get(e, ()))
    for i in cand:
        ex = cliques[i][0]
        if all(e in oc for e in ex):
            evaluated_runs[i] += 1
            fam[i][g].add(tuple("B" if len(oc[e]) == 2 else ("T" if True in oc[e] else "F") for e in ex))
    del raw, run
    if k % 5000 == 0: print(f"  {k} dumps, {time.time()-t0:.0f}s", flush=True)
print(f"scanned {len(files)} ({bad} bad) groups={dict(ngroup)} in {time.time()-t0:.0f}s", flush=True)

VAR = re.compile(r"SYM_[A-Za-z0-9_]+")
def matches(combo, family):
    return all(f == "B" or (f == "T") == c for c, f in zip(combo, family))

undeclared = set(); res = []; tot = collections.Counter(); per_width = collections.defaultdict(collections.Counter)
for i, (ex, wit) in enumerate(cliques):
    vars_ = sorted({v for e in ex for v in VAR.findall(e)})
    dl = []
    for v in vars_:
        if v in decls: dl.append(decls[v]); continue
        # not declared by any scanned dump (sample): infer the sort from use
        txt = " ".join(e for e in ex if v in e)
        sort = "String" if "StringVal(" in txt or "== ''" in txt else ("Bool" if "== True" in txt or "== False" in txt else "Int")
        dl.append(f"{v} = {sort}('{v}')"); undeclared.add(v)
    fixed = []
    for v in vars_:
        if v in bounds: fixed += [f"{v} >= {bounds[v][0]}", f"{v} <= {bounds[v][1]}"]
    # Direct incremental Z3 enumeration (same namespace/decls as the engine's
    # solver): one check() per satisfiable outcome tuple + one blocking clause.
    env = dict(_Z3_NAMESPACE)
    for d in dl: exec(d, {"__builtins__": {}}, env)
    zex = [eval(e, {"__builtins__": {}}, env) for e in ex]
    s = z3.Solver(); s.set("timeout", 5000)
    for f in fixed: s.add(eval(f, {"__builtins__": {}}, env))
    sat = []; capped = False; unknown = False
    while True:
        if len(sat) >= CAP: capped = True; break
        r = s.check()
        if r == z3.unknown: unknown = True; break
        if r == z3.unsat: break
        mdl = s.model()
        combo = tuple(z3.is_true(mdl.eval(z, model_completion=True)) for z in zex)
        sat.append(combo)
        s.add(z3.Not(z3.And(*[z if o else z3.Not(z) for z, o in zip(zex, combo)])))
    allfam = set().union(*fam[i].values()) if fam[i] else set()
    fam_no_new = set().union(*(s for g, s in fam[i].items() if g not in ("DV_v2", "PV_pilot"))) if fam[i] else set()
    cov_all = sum(1 for c in sat if any(matches(c, f) for f in allfam))
    cov_old = sum(1 for c in sat if any(matches(c, f) for f in fam_no_new))
    wit_cov = any(matches(wit, f) for f in allfam)
    wit_sat = wit in sat
    w = len(ex)
    row = dict(i=i, width=w, nvars=len(vars_), sat=len(sat), capped=capped, unknown=unknown, covered=cov_all, covered_before_v2=cov_old,
               remaining=len(sat) - cov_all, evaluated_runs=evaluated_runs[i], witness_sat=wit_sat, witness_covered=wit_cov,
               groups={g: len(s) for g, s in fam[i].items()})
    res.append(row)
    for kk in ("sat", "covered", "covered_before_v2", "remaining"): tot[kk] += row[kk]; per_width[w][kk] += row[kk]
    tot["capped"] += capped; tot["unknown"] += unknown; tot["closed_now"] += (row["remaining"] == 0); tot["witness_covered"] += wit_cov; tot["witness_unsat"] += (not wit_sat)
    per_width[w]["cliques"] += 1; per_width[w]["closed"] += (row["remaining"] == 0)
    if i % 200 == 0: print(f"  clique {i}: {time.time()-t0:.0f}s", flush=True)
json.dump({"totals": dict(tot), "per_width": {w: dict(c) for w, c in sorted(per_width.items())}, "groups": dict(ngroup), "cliques": res}, open(OUT, "w"), indent=1)
print("TOTALS:", dict(tot)); print("vars declared by no scanned dump (sort inferred):", len(undeclared))
print("per width:")
for w, c in sorted(per_width.items()): print(f"  w={w:2d} cliques={c['cliques']:4d} sat={c['sat']:6d} covered={c['covered']:6d} (before v2 {c['covered_before_v2']:6d}) remaining={c['remaining']:6d} closed={c['closed']}")
print(f"done in {time.time()-t0:.0f}s -> {OUT}")
