#!/usr/bin/env python3
"""Checker-demanded exploration roots, built ON TOP OF A REAL DUMP'S SEEDS.

Why not `demand_round.py`: it seeds ONLY the clique variables the checker
named, so every other dimension falls back to its default. A combination whose
decisions are only evaluated in a particular context (an STI type, a non-empty
list, a mention-bearing text) is then never reached at all — the replay simply
re-walks the default path and the missing entry survives round after round.

This builds each root as  BASE SEEDS OF A REAL DUMP  +  the demanded
assignment: the base is the corpus dump that records the most of the
combination's expressions (preferring the same variant and, for each
expression, the OTHER polarity), so the context that evaluates them is
reproduced and only the demanded decisions are flipped.

    MAX_MISSING_PER_CLIQUE=<n> PYTHONPATH=src python3 coverage_report.py   # SKIP_COMPLETION=1
    python3 _demand_root.py [--tag TAG]      # writes _demandR_<variant>.json
"""
import glob, json, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")

summary = json.load(open(os.path.join(HERE, "coverage_summary.json")))
missing = [m for m in summary.get("missing", []) if not m.get("untracked")]
print(f"missing (blocking): {len(missing)}")

# ---- corpus index (LEAN: only the exprs the missing set mentions are kept
# per dump — a full {expr: taken} map over 20k dumps is gigabytes) ----------
_WANTED = set()
for _m in missing:
    for _part in (_m.get("node_constraint") or "").split(" AND "):
        _part = _part.strip()
        _mm = re.match(r"^Not\((.*)\)$", _part, re.S)
        if _mm:
            _part = _mm.group(1).strip()
        elif _part.startswith("NOT "):
            _part = _part[4:].strip()
        _WANTED.add(_part)
        _WANTED.add(re.sub(r"SYM_LEN_([A-Za-z0-9_]+)", r"len(\1)", _part))

dumps = []            # (variant, seeds, {expr: taken})  -- wanted exprs only
expr_variants = defaultdict(set)
for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json"))):
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), None)
    try:
        d = json.load(open(p))
    except Exception:
        continue
    pcs = {}
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            ex = e["expr"]
            expr_variants[ex].add(v)
            if ex in _WANTED:
                pcs[ex] = bool(e.get("taken"))
    dumps.append((v, d.get("concolic_seeds") or {}, pcs))
    del d
print(f"indexed {len(dumps)} dumps, {len(expr_variants)} distinct exprs, "
      f"{len(_WANTED)} wanted")

_LEN = re.compile(r"len\(([^()]+)\)")
fixed_to_orig = {_LEN.sub(r"SYM_LEN_\1", e): e for e in expr_variants}


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


def conjuncts(nc):
    """node_constraint -> [(expr, wanted_polarity)]"""
    out = []
    for part in nc.split(" AND "):
        part = part.strip()
        want = True
        m = re.match(r"^Not\((.*)\)$", part, re.S)
        if m:
            part, want = m.group(1).strip(), False
        elif part.startswith("NOT "):
            part, want = part[4:].strip(), False
        out.append((part, want))
    return out


per_variant = {v: [] for v in VARIANTS}
seen = {v: set() for v in VARIANTS}
no_base = 0
for m in missing:
    cj = conjuncts(m.get("node_constraint") or "")
    origs = []
    for x, want in cj:
        o = fixed_to_orig.get(x) or (x if x in expr_variants else None)
        if o:
            origs.append((o, want))
    # variants that record every expr of the combination
    vs = None
    for o, _w in origs:
        s_ = expr_variants[o]
        vs = set(s_) if vs is None else (vs & s_)
    vs = vs or set(VARIANTS)
    # ONLY the variables the COMBINATION constrains may be overlaid. The Z3
    # model assigns EVERY variable in the clique's declaration set, and its
    # defaults are 0 — including every list length — so overlaying the whole
    # model seeds `len(...to_ary_1_rows) = 0`, which FORECLOSES the very
    # decisions the combination is about (they live on rows that then do not
    # exist). That is why two full demand rounds moved BLOCKING 478 -> 478.
    # Overlay the constrained variables onto a REAL dump's seeds and leave the
    # rest of that dump's context alone.
    want = set()
    for _o, _w in origs:
        for tok in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", _o):
            want.add(tok)
            if tok.startswith("SYM_LEN_"):
                want.add("len(" + tok[8:] + ")")
    demanded = {unfix(k): to_seed(v) for k, v in (m.get("concrete_values") or {}).items()
                if k in want or unfix(k) in want}
    # best base dump: records the most of the combination's exprs; among ties
    # prefer one whose polarities DIFFER from the demand (the "other polarity"
    # dump the coordinator asked for) and whose variant is in vs.
    best, bestscore = None, (-1, -1, -1)
    for (v, seeds, pcs) in dumps:
        hit = sum(1 for o, _w in origs if o in pcs)
        if hit == 0:
            continue
        opp = sum(1 for o, w in origs if o in pcs and pcs[o] != w)
        score = (hit, opp, 1 if v in vs else 0)
        if score > bestscore:
            best, bestscore = (v, seeds), score
    if best is None:
        no_base += 1
        base_seeds, base_v = {}, None
    else:
        base_v, base_seeds = best[0], best[1]
    seed = dict(base_seeds)
    seed.update(demanded)
    if not seed:
        continue
    targets = sorted(vs) if vs else ([base_v] if base_v else list(VARIANTS))
    if base_v and base_v not in targets:
        targets.append(base_v)
    key = json.dumps(seed, sort_keys=True)
    for v in targets:
        if v is None or key in seen[v]:
            continue
        seen[v].add(key)
        per_variant[v].append(seed)

for v, lst in per_variant.items():
    out = os.path.join(HERE, f"_demandR_{v}.json")
    if lst:
        json.dump(lst, open(out, "w"))
    elif os.path.exists(out):
        os.remove(out)
    print(f"{v}: {len(lst)} rooted seed dicts")
print(f"combinations with no corpus base: {no_base}")
