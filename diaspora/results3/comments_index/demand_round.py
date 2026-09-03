#!/usr/bin/env python3
"""Checker-demanded exploration round (RUNBOOK Phase 2 "rounds"): turn the
coverage checker's MISSING combinations (coverage_summary.json `missing[]`,
each carrying a Z3 model over the clique's vars) into per-variant seed
files for run_dse.rb's EXTRA_SEEDS_JSON knob. The DSE then replays each
demanded assignment as a worklist ROOT (and keeps flipping from it), so the
next checker run sees the combination in a single run's path.

    MAX_MISSING_PER_CLIQUE=500 PYTHONPATH=src python3 coverage_report.py
    python3 demand_round.py            # writes _demand_<variant>.json
    VARIANT=<v> EXTRA_SEEDS_JSON=_demand_<v>.json ... run_dse.rb

Var-name mapping: coverage_report.py renames `len(X)` -> `SYM_LEN_X` for the
solver; the runner seeds the literal `len(X)` key. Variant attribution: a
missing combo's exprs are looked up in the corpus's expr->variant map; the
seed goes to every variant that records ALL of the combo's exprs.
"""
import glob, json, os, sys, re
HERE = os.path.dirname(os.path.abspath(__file__))
VARIANTS = ("anon_json", "auth_json", "anon_mobile", "auth_mobile")

summary = json.load(open(os.path.join(HERE, "coverage_summary.json")))
missing = [m for m in summary.get("missing", []) if not m.get("untracked")]

expr_variants = {}
# BASE SEEDS (cycle 3): a witness's Z3 model covers only the clique's own
# vars; to REACH that clique the replay needs the prerequisites (e.g. the
# comment unpersisted + mention-bearing text before any lookup-chain
# decision exists). Per dump, remember its seed dict and the exprs it
# recorded; each witness is merged onto the seed dict of a dump (same
# variant) that evaluated every expr of the combo.
dump_seeds = []   # (variant, exprs_set, seeds)
for p in glob.glob(os.path.join(HERE, "dump_*.json")):
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), None)
    d = json.load(open(p))
    ex = set()
    for e in d.get("events") or []:
        if e.get("type") == "path_condition":
            expr_variants.setdefault(e["expr"], set()).add(v)
            ex.add(e["expr"])
    dump_seeds.append((v, ex, d.get("concolic_seeds") or {}))

def unfix(name):
    return f"len({name[8:]})" if name.startswith("SYM_LEN_") else name

def to_seed(v):
    if isinstance(v, bool) or v is None:
        return v
    if isinstance(v, (int, float)):
        return int(v)
    s = str(v)
    if s in ("True", "False"):
        return s == "True"
    try:
        return int(s)
    except ValueError:
        return s.strip('"')

import re
fixed_to_orig = {re.sub(r"len\(([^()]+)\)", r"SYM_LEN_\1", e): e for e in expr_variants}

per_variant = {v: [] for v in VARIANTS}
seen = {v: set() for v in VARIANTS}
unattributed = 0
for m in missing:
    exprs = [x.strip().replace("NOT ", "") for x in m["node_constraint"].split(" AND ")]
    vs = None
    for x in exprs:
        orig = fixed_to_orig.get(x) or (x if x in expr_variants else None)
        if orig is None:
            continue
        s_ = expr_variants[orig]
        vs = set(s_) if vs is None else (vs & s_)
    if not vs:
        unattributed += 1
        vs = set(VARIANTS)
    # Only vars that occur in the combo's own exprs are seeded from the Z3
    # model: a model also assigns every declared var (all SYM_LEN_* lengths
    # -> 0 = an EMPTY comment list), which would make the replay never reach
    # the clique (found live: demand rounds added no paths).
    combo_vars = set(re.findall(r"[A-Za-z_][A-Za-z0-9_()]*", m["node_constraint"]))
    wit = {unfix(k): to_seed(v) for k, v in (m.get("concrete_values") or {}).items()
           if k in combo_vars or unfix(k) in combo_vars}
    if not wit:
        continue
    orig_exprs = {fixed_to_orig.get(x) or x for x in exprs}
    for v in sorted(vs):
        # smallest base seed dict (same variant) whose run evaluated every expr of the combo
        bases = [sd for (dv, ex, sd) in dump_seeds if dv == v and orig_exprs <= ex]
        base = min(bases, key=len) if bases else {}
        seeds = dict(base); seeds.update(wit)
        key = json.dumps(seeds, sort_keys=True)
        if key in seen[v]:
            continue
        seen[v].add(key)
        per_variant[v].append(seeds)

for v, lst in per_variant.items():
    out = os.path.join(HERE, f"_demand_{v}.json")
    if lst:
        json.dump(lst, open(out, "w"))
    elif os.path.exists(out):
        os.remove(out)
    print(f"{v}: {len(lst)} demanded seed dicts")
print(f"missing entries: {len(missing)}; unattributed (sent to all variants): {unattributed}")
