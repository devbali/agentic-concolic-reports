#!/usr/bin/env python3
"""Checker-demanded exploration round (RUNBOOK Phase 2 "rounds"): turn the
coverage checker's MISSING combinations (coverage_summary.json `missing[]`,
each carrying a Z3 model over the clique's vars) into per-variant seed
files for run_dse.rb's EXTRA_SEEDS_JSON knob. The DSE then replays each
demanded assignment as a worklist ROOT (and keeps flipping from it), so the
next checker run sees the combination in a single run's path.

    MAX_MISSING_PER_CLIQUE=500 PYTHONPATH=src python3 coverage_report.py
    python3 demand_round.py            # writes _demand_<variant>.json
    VARIANTS=<v> EXTRA_SEEDS_JSON=_demand_<v>.json ... run_dse.rb

Var-name mapping: coverage_report.py renames `len(X)` -> `SYM_LEN_X` for the
solver; the runner seeds the literal `len(X)` key. Variant attribution: a
missing combo's exprs are looked up in the corpus's expr->variant map; the
seed goes to every variant that records ALL of the combo's exprs.
"""
import glob, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed", "mobile_plain", "mobile_typed", "xml_plain")

summary = json.load(open(os.path.join(HERE, "coverage_summary.json")))
missing = [m for m in summary.get("missing", []) if not m.get("untracked")]

expr_variants = {}
for p in glob.glob(os.path.join(HERE, "dump_*.json")):
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), None)
    d = json.load(open(p))
    for e in d.get("events") or []:
        if e.get("type") == "path_condition":
            expr_variants.setdefault(e["expr"], set()).add(v)

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
    seeds = {unfix(k): to_seed(v) for k, v in (m.get("concrete_values") or {}).items()}
    if not seeds:
        continue
    key = json.dumps(seeds, sort_keys=True)
    for v in sorted(vs):
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
