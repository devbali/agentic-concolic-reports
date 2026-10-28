#!/usr/bin/env python3
"""CAMPAIGN MEASURE (2026-09-09): incremental "assignments covered" between
coverage passes. NOT the judge — the engine's coverage pass is. This is the
cheap progress meter: it keeps per-run outcome families (through the engine's
load path: canonicalize_ordinals -> fix_len_names -> Run.from_dict ->
apply_len_bounds) in `_campaign_families.json.gz`, scans only NEW dumps, and
counts covered / remaining satisfiable assignments per clique under the graph
of the LATEST coverage_summary.json (complete-minus-declared, Bron-Kerbosch,
exact Z3 enumeration per variable-connected component — cmodel.py's method,
which reproduced the summary's 1 826 cliques exactly on 2026-09-09).

usage: python3 _campaign_measure.py [--summary FILE] [--groups TAG1,TAG2,...]
       [--no-scan] [--note TEXT]
  --groups: also report covered WITHOUT each listed tag (marginal yield per tag)
Appends one line to _campaign_measure_history.jsonl.
"""
import json, gzip, os, re, sys, time, collections, itertools, argparse
H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, H)
ap = argparse.ArgumentParser()
ap.add_argument("--summary", default=os.path.join(H, "coverage_summary.json"))
ap.add_argument("--groups", default="")
ap.add_argument("--no-scan", action="store_true")
ap.add_argument("--note", default="")
ap.add_argument("--state", default=os.path.join(H, "_campaign_families.json.gz"))
A = ap.parse_args()
t0 = time.time()
STATE = A.state
SATC = os.path.join(H, "_campaign_satcache.json")

# ---------- 1. state: per-run outcome families ----------
if os.path.exists(STATE):
    F = json.load(gzip.open(STATE, "rt"))
else:
    F = json.load(gzip.open(os.path.join(H, "_campaign_families_seed_68231.json.gz"), "rt"))
    for r in F["runs"]: r.pop("fb", None)
    F["badfiles"] = []
EXPRS = F["exprs"]; EIDX = {e: i for i, e in enumerate(EXPRS)}
have = set(r["f"] for r in F["runs"]) | set(F.get("badfiles", []))
nnew = 0; nbad = 0
if not A.no_scan:
    from coverage_report import canonicalize_ordinals, fix_len_names, apply_len_bounds
    from concolic_engine.run import Run
    import logging; logging.getLogger("concolic_engine.solver").setLevel(logging.ERROR)
    now = time.time()
    files = []
    with os.scandir(H) as it:
        for de in it:
            n = de.name
            if n.startswith("dump_") and n.endswith(".json") and n not in have:
                try:
                    if now - de.stat().st_mtime < 15: continue   # may be mid-write
                except FileNotFoundError: continue
                files.append(n)
    files.sort()
    print(f"scanning {len(files)} new dumps (state has {len(F['runs'])})", flush=True)
    for k, fn in enumerate(files):
        try:
            raw = json.load(open(os.path.join(H, fn)))
            canonicalize_ordinals(raw)
            run = apply_len_bounds(Run.from_dict(fix_len_names(raw)))
        except Exception as e:
            nbad += 1; F.setdefault("badfiles", []).append(fn); continue
        for sv, d in zip(run.symbolic_vars, run.z3_declarations()):
            F["decls"].setdefault(sv.name, d)
            if sv.low is not None and sv.high is not None: F["bounds"].setdefault(sv.name, [sv.low, sv.high])
        oc = {}
        for pc in run.path_conditions:
            i = EIDX.get(pc.expr)
            if i is None:
                i = len(EXPRS); EXPRS.append(pc.expr); EIDX[pc.expr] = i
            oc[i] = oc.get(i, 0) | (1 if pc.taken else 2)
        F["runs"].append({"f": fn, "l": run.label, "o": [[i, v] for i, v in oc.items()]})
        nnew += 1
        del raw, run
        if k % 5000 == 0 and k: print(f"  {k} scanned, {time.time()-t0:.0f}s", flush=True)
    F["exprs"] = EXPRS
    tmp = STATE + ".tmp"
    json.dump(F, gzip.open(tmp, "wt")); os.replace(tmp, STATE)
    print(f"state saved: {len(F['runs'])} runs (+{nnew}, {nbad} bad) {time.time()-t0:.0f}s", flush=True)
RUNS = F["runs"]; DECLS = F["decls"]; BOUNDS = F["bounds"]

# ---------- 2. graph from the summary ----------
d = json.load(open(A.summary))
indep = set(); untracked = set(); oneside = {}
for a in d["assumptions"]:
    if a["type"] == "IndependenceAssumption": indep.add(frozenset((a["expr_a"], a["expr_b"])))
    elif a["type"] == "UntrackedPathAssumption": untracked.add(a["expr"])
    elif a["type"] == "OneSideUntrackedPathAssumption": oneside[a["expr"]] = a["tracked_side"]
miss = [m for m in d["missing"] if not m.get("untracked")]
uni = set()
for m in miss:
    for part in m["node_constraint"].split(" AND "):
        part = part.strip(); mm = re.match(r"^Not\((.*)\)$", part, re.S)
        uni.add(mm.group(1).strip() if mm else part)
for p in indep: uni |= set(p)
uni |= untracked; uni |= set(oneside)
print(f"summary: total_runs={d['total_runs']} missing={d['missing_branches']} (json {len(d['missing'])}) "
      f"universe={len(uni)} tree_nodes={d['tree_nodes']} indep={len(indep)} untracked={len(untracked)} oneside={len(oneside)}", flush=True)
active = sorted(e for e in uni if e not in untracked)
adj = {e: set() for e in active}
for i, a in enumerate(active):
    for b in active[i+1:]:
        if frozenset((a, b)) in indep: continue
        adj[a].add(b); adj[b].add(a)
cliques = []
def bk(r, p, x):
    if not p and not x: cliques.append(sorted(r)); return
    pivot = max(p | x, key=lambda v: len(adj[v] & p))
    for v in list(p - adj[pivot]):
        bk(r | {v}, p & adj[v], x & adj[v]); p = p - {v}; x = x | {v}
bk(set(), set(active), set())
print(f"maximal cliques: {len(cliques)} (max width {max(len(c) for c in cliques)}) {time.time()-t0:.0f}s", flush=True)

# ---------- 3. satisfiable assignments per clique (cached) ----------
from concolic_engine.solver import _Z3_NAMESPACE
import z3
VAR = re.compile(r"SYM_[A-Za-z0-9_]+")
satc = json.load(open(SATC)) if os.path.exists(SATC) else {}
def sat_assignments(exprs):
    key = "|".join(exprs)
    if key in satc: return [tuple(ch == "T" for ch in s) for s in satc[key]]
    vars_of = [set(VAR.findall(e)) for e in exprs]
    n = len(exprs); parent = list(range(n))
    def find(a):
        while parent[a] != a: parent[a] = parent[parent[a]]; a = parent[a]
        return a
    byvar = collections.defaultdict(list)
    for i, vs in enumerate(vars_of):
        for v in vs: byvar[v].append(i)
    for v, idx in byvar.items():
        for j in idx[1:]: parent[find(j)] = find(idx[0])
    comps = collections.defaultdict(list)
    for i in range(n): comps[find(i)].append(i)
    per = []
    for idx in comps.values():
        vs = set().union(*(vars_of[i] for i in idx))
        env = dict(_Z3_NAMESPACE)
        for v in vs:
            dd = DECLS.get(v)
            if dd is None:
                txt = " ".join(exprs[i] for i in idx if v in exprs[i])
                sort = "String" if "StringVal(" in txt or "== ''" in txt else ("Bool" if "== True" in txt or "== False" in txt else "Int")
                dd = f"{v} = {sort}('{v}')"
            exec(dd, {"__builtins__": {}}, env)
        s = z3.Solver(); s.set("timeout", 5000)
        for v in vs:
            if v in BOUNDS:
                lo, hi = BOUNDS[v]; s.add(eval(f"{v} >= {lo}", {"__builtins__": {}}, env)); s.add(eval(f"{v} <= {hi}", {"__builtins__": {}}, env))
        zs = [eval(exprs[i], {"__builtins__": {}}, env) for i in idx]
        sols = []
        while True:
            if s.check() != z3.sat: break
            m = s.model(); combo = tuple(z3.is_true(m.eval(zz, model_completion=True)) for zz in zs)
            sols.append(combo); s.add(z3.Not(z3.And(*[zz if o else z3.Not(zz) for zz, o in zip(zs, combo)])))
            if len(sols) > 70000: raise RuntimeError("component too large")
        per.append((idx, sols))
    out = []
    for choice in itertools.product(*(sols for _, sols in per)):
        t = [None] * n
        for (idx, _), sol in zip(per, choice):
            for i, o in zip(idx, sol): t[i] = o
        out.append(tuple(t))
    satc[key] = ["".join("T" if o else "F" for o in t) for t in out]
    return out

# ---------- 4. coverage ----------
runs_of = collections.defaultdict(set)   # expr idx -> run ids
omap = []
for rid, r in enumerate(RUNS):
    o = dict(r["o"]); omap.append(o)
    for i in o: runs_of[i].add(rid)
def tag_of(fn):
    m = re.search(r"_dse\d+(.*)\.json$", fn); return m.group(1) if m else ""
tags = [tag_of(r["f"]) for r in RUNS]
groups = [g for g in A.groups.split(",") if g]
excl_sets = {g: set(rid for rid, t in enumerate(tags) if g in t) for g in groups}
def covered_count(sat, fams):
    if not fams: return 0
    if any(all(f == 3 for f in fam) for fam in fams): return len(sat)
    c = 0
    for s in sat:
        for fam in fams:
            if all(f == 3 or (f == 1) == o for f, o in zip(fam, s)): c += 1; break
    return c
tot = collections.Counter(); per_w = collections.defaultdict(collections.Counter)
excl_tot = collections.Counter(); rows = []
for c in cliques:
    sat = sat_assignments(c)
    idx = [EIDX.get(e) for e in c]
    if any(i is None for i in idx): ev = set()
    else:
        ev = None
        for i in sorted(idx, key=lambda i: len(runs_of[i])):
            ev = runs_of[i] if ev is None else (ev & runs_of[i])
            if not ev: break
        ev = ev or set()
    fams = set(tuple(omap[rid][i] for i in idx) for rid in ev)
    cov = covered_count(sat, fams)
    w = len(c)
    tot["cliques"] += 1; tot["sat"] += len(sat); tot["covered"] += cov; tot["remaining"] += len(sat) - cov
    tot["closed"] += (cov == len(sat)); tot["never_coeval"] += (not ev)
    per_w[w]["cliques"] += 1; per_w[w]["sat"] += len(sat); per_w[w]["remaining"] += len(sat) - cov; per_w[w]["closed"] += (cov == len(sat))
    for g, ex in excl_sets.items():
        fams_g = set(tuple(omap[rid][i] for i in idx) for rid in ev if rid not in ex)
        excl_tot[g] += covered_count(sat, fams_g)
    rows.append({"width": w, "sat": len(sat), "covered": cov, "evaluated_runs": len(ev), "exprs": c})
json.dump(satc, open(SATC, "w"))
ngr = collections.Counter(tags)
line = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "runs": len(RUNS), "new_scanned": nnew, "summary_runs": d["total_runs"],
        "cliques": tot["cliques"], "sat": tot["sat"], "covered": tot["covered"], "remaining": tot["remaining"],
        "closed": tot["closed"], "never_coeval": tot["never_coeval"], "note": A.note,
        "marginal": {g: {"runs": len(excl_sets[g]), "assignments": tot["covered"] - excl_tot[g]} for g in groups}}
print(f"RESULT runs={len(RUNS)} cliques={tot['cliques']} sat={tot['sat']} covered={tot['covered']} remaining={tot['remaining']} "
      f"closed={tot['closed']} never_coeval={tot['never_coeval']} ({time.time()-t0:.0f}s)", flush=True)
for w, c in sorted(per_w.items()): print(f"   w={w:2d} cliques={c['cliques']:5d} sat={c['sat']:7d} remaining={c['remaining']:7d} closed={c['closed']}")
for g in groups:
    n = len(excl_sets[g]); y = tot["covered"] - excl_tot[g]
    print(f"   marginal[{g}]: runs={n} assignments={y} ({y/n if n else 0:.3f}/run)")
with open(os.path.join(H, "_campaign_measure_history.jsonl"), "a") as fh: fh.write(json.dumps(line) + "\n")
json.dump({"line": line, "per_width": {w: dict(c) for w, c in sorted(per_w.items())}, "rows": rows},
          open(os.path.join(H, "_campaign_measure_last.json"), "w"))
