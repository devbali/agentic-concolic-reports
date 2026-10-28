#!/usr/bin/env python3
"""ENABLING-CONSTRAINT roots: seeds built from the counterexample AND the
graph structure (owner direction, 2026-09-10, §14).

WHY. `_demand_root.py` roots a seed on a real dump and overlays only the
variables the cube CONSTRAINS. That reproduces a context, but not necessarily
one in which the cube's members are all EVALUABLE: §12.10 measured that 70 %
of every rooted seed's keys are never evaluated at all, which is why even the
best rooted method converts at 0.157/run. A cube is a conjunction, so a run
that reaches 30 % of its members realises it only by luck.

WHAT IS DIFFERENT HERE. The engine already knows which decisions gate which:
§16b's INFERRED foreclosure relation, `(g, o) -> d`, meaning "no run that took
`g = o` ever evaluated `d`". So for every member `d` of a cube, and every
`(g, o)` that forecloses `d`, the walk we want must have `g != o`. Adding
those disequalities to the solver query — transitively, over the gates of
those gates — turns the counterexample into a COMPLETE, WALKABLE assignment:
the cube's own outcomes PLUS every upstream gate setting under which all of
its members are evaluable. The model then carries the path, not just the leaf.

The base is then chosen by COMPATIBILITY rather than richness (§13.1's test,
applied per witness): a run whose profile evaluates all of the cube's members
AND whose gate outcomes agree with the model. For the 93.5 % REACHABLE cubes
such a run exists by construction — that is what "reachable" was measured to
mean. The model's assignment (members + enabling gates, never the whole model
— a Z3 default of 0 on every list length forecloses the very decisions the
cube is about, §12.10) is overlaid on that base's seeds, with the SELF-COMPARE
UNSEED rule of §12.5 applied last.

inputs   coverage_summary.json (or SUMMARY_IN)   -- the witness cubes
         _forecl.json (or FORECL_IN)             -- _forecl_dump.py's relation
         DUMP_LIST                               -- the base corpus snapshot
outputs  _enableR_<variant>.json                 -- seed dicts, one per variant
         _enable_plan.json                       -- per-cube provenance, for the
                                                    post-round §12.10 audit
env      MAX_ENABLE_DEPTH (3)  transitive gate layers
         DEMAND_BASES (1)      bases per witness (owner: one)
         UNSEED_SELFCMP (1)    the §12.5 presence rule
"""
import json, os, re, sys, time
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.solver import check_satisfiability          # noqa: E402
from concolic_engine.coverage import _outcome_constraint          # noqa: E402
from coverage_report import canonicalize_ordinals                 # noqa: E402

VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
TIMEOUT = int(os.environ.get("Z3_TIMEOUT_MS", "10000"))
MAX_DEPTH = int(os.environ.get("MAX_ENABLE_DEPTH", "3"))
NBASES = int(os.environ.get("DEMAND_BASES", "1"))
UNSEED = os.environ.get("UNSEED_SELFCMP", "1") != "0"
TAG = os.environ.get("TAG", "E1")
ONE_VARIANT = os.environ.get("ONE_VARIANT", "1" if os.environ.get("TARGETS") else "0") != "0"

# T10 stays environmentally unreachable (§7.7); T1/T2 are drivable since the
# §5h-bis wall (§9.2), so only the one entry remains.
_UNREACHABLE = {
    ("(SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_username == '')", True),
}
_SELFCMP = re.compile(r"^\((SYM_[A-Za-z0-9_]+) == \1__prior\)$")
_LEN = re.compile(r"len\(([^()]+)\)")
_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def selfcmp_var(expr):
    m = _SELFCMP.match(expr.strip())
    return m.group(1) if m else None


def conjuncts(nc):
    out = []
    for part in (nc or "").split(" AND "):
        part = part.strip()
        want = True
        m = re.match(r"^Not\((.*)\)$", part, re.S)
        if m:
            part, want = m.group(1).strip(), False
        elif part.startswith("NOT "):
            part, want = part[4:].strip(), False
        if part:
            out.append((part, want))
    return out


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


def unfix(name):
    return f"len({name[8:]})" if name.startswith("SYM_LEN_") else name


# ---------------------------------------------------------------- inputs ---
# TARGETS (2026-09-10, §16 owner direction): the targets are the EXACT
# remaining set emitted by `_exact_enum.py` (EMIT_REMAINING), not the
# checker's capped `missing[]`. The enumerator names EVERY remaining
# assignment in ~100 s where a `coverage_report.py` pass takes 3 h to name a
# capped handful, and it labels each one REACHABLE or MULTI-GATE-FORECLOSED,
# so the 1 560 declared-residue cubes are skipped and COUNTED rather than
# driven. `SUMMARY_IN` remains supported for the old path.
_TARGETS = os.environ.get("TARGETS")
skipped_unreach_group = 0
if _TARGETS:
    missing = []
    with open(_TARGETS) as fh:
        for line in fh:
            if not line.strip():
                continue
            r = json.loads(line)
            if not r.get("reachable"):
                skipped_unreach_group += 1     # §13.3's declared residue
                continue
            full = dict(r.get("pre") or {})
            full.update(r.get("asg") or {})
            missing.append({
                "node_constraint": " AND ".join(
                    (e if v else f"Not({e})") for e, v in sorted(full.items())),
                "set": r.get("set"), "width": r.get("width"),
                "untracked": False,
            })
    print(f"TARGETS {_TARGETS}: {len(missing)} REACHABLE remaining assignments; "
          f"{skipped_unreach_group} MULTI-GATE-FORECLOSED skipped (declared "
          f"residue, §13.3)")
else:
    summary = json.load(open(os.environ.get("SUMMARY_IN")
                             or os.path.join(HERE, "coverage_summary.json")))
    missing = [m for m in summary.get("missing", []) if not m.get("untracked")]
    print(f"missing (blocking): {len(missing)}")

F = json.load(open(os.environ.get("FORECL_IN") or os.path.join(HERE, "_forecl.json")))
decls, fixed_base = F["decls"], F["fixed_base"]
# (g, o) -> set(d):  invert to  d -> [(g, o)]
gated_by = defaultdict(list)
for g, byo in F["gates"].items():
    for ok, ds in byo.items():
        o = (ok == "1")
        for d in ds:
            gated_by[d].append((g, o))
print(f"foreclosure relation: {F['pairs']} pairs over {len(F['gates'])} gates, "
      f"{len(gated_by)} gated decisions (from {F.get('dump_list')})")
KNOWN = {d.split("=", 1)[0].strip() for d in decls}


def enabling(members, depth):
    """Transitive enabling closure.

    `members` are the exprs the cube needs EVALUATED. For each, every `(g, o)`
    that forecloses it must be AVOIDED, so the walk must not have `g = o`;
    since `g` is a boolean decision that leaves `g` taking the other outcome,
    which makes `g` itself something the walk must evaluate — one layer up.

    CONFLICTS ARE NOT FATAL, and this is the one place the constraint is
    weaker than it looks. `(g, o)` forecloses `d` means "no run with `g = o`
    evaluated `d`" — it does NOT speak about a run that never evaluates `g` at
    all. So when two members of the same cube are foreclosed by OPPOSITE
    outcomes of the same `g`, the resolution is not "this cube is impossible":
    it is "`g` must not be evaluated in this walk", which is not expressible as
    a Z3 constraint over `g`. Such a gate is therefore left FREE (dropped from
    `req`) and counted. Measured on the smoke corpus: 0 conflicts at depth 1,
    and they appear only in the transitive layers, where the relation is at
    its most over-inferred.

    Returns (req, freed): `req` maps gate -> the outcome it must take; `freed`
    is the set of gates dropped for the reason above.
    """
    req, freed = {}, set()
    frontier, seen = set(members), set(members)
    for _ in range(depth):
        nxt = set()
        for d in frontier:
            for g, o in gated_by.get(d, ()):
                if g in members or g in freed:
                    continue                      # the cube itself fixes it
                want = not o
                if req.get(g, want) != want:
                    freed.add(g)
                    req.pop(g, None)
                    nxt.discard(g)
                    continue
                req[g] = want
                if g not in seen:
                    seen.add(g)
                    nxt.add(g)
        if not nxt:
            break
        frontier = nxt
    return req, freed


def solve(cube, req):
    cons = list(fixed_base)
    cons += [_outcome_constraint(e, w) for e, w in cube]
    cons += [_outcome_constraint(g, w) for g, w in req.items()]
    return check_satisfiability(cons, decls, TIMEOUT)


# -------------------------------------------- 1. cubes -> models (no dumps) --
t0 = time.time()
plans = []
stat = defaultdict(int)
depth_hist = defaultdict(int)
for mi, m in enumerate(missing):
    if mi and mi % 500 == 0:
        print(f"  solving [{mi}/{len(missing)}] kept={len(plans)} "
              f"{time.time()-t0:.0f}s", flush=True)
    cube = conjuncts(m.get("node_constraint"))
    if any((x, w) in _UNREACHABLE for x, w in cube):
        stat["skip_unreachable"] += 1
        continue
    members = [x for x, _w in cube]
    req_full, freed = enabling(members, MAX_DEPTH)
    if freed:
        stat["cubes_with_freed_gates"] += 1
        stat["freed_gates"] += len(freed)
    # Back off the transitive layers until the query is SAT: a deep closure
    # can over-constrain (the relation is inferred, so a `g != o` may be a
    # corpus correlation rather than a gating). The depth that survives is
    # RECORDED, because a cube that only solves at depth 0 is one whose
    # enabling constraints we could not use.
    res, used = None, None
    for d in range(MAX_DEPTH, -1, -1):
        req = req_full if d == MAX_DEPTH else enabling(members, d)[0]
        r = solve(cube, req)
        if r.satisfiable and r.model:
            res, used, req_used = r, d, req
            break
    if res is None:
        stat["unsat_even_bare"] += 1
        plans.append(dict(idx=mi, status="unsat", cube=cube))
        continue
    depth_hist[used] += 1
    stat["solved"] += 1
    plans.append(dict(idx=mi, status="ok", cube=cube, depth=used,
                      freed=sorted(freed)[:20], n_freed=len(freed),
                      req={g: bool(w) for g, w in req_used.items()},
                      model={k: to_seed(v) for k, v in res.model.items()}))
print(f"solved {stat['solved']} of {len(missing)}: "
      f"unsat {stat['unsat_even_bare']}, "
      f"skipped-unreachable {stat['skip_unreachable']}  ({time.time()-t0:.0f}s)")
print(f"cubes with a FREED gate (both outcomes foreclose a member, so the gate "
      f"must simply not be evaluated): {stat['cubes_with_freed_gates']}, "
      f"{stat['freed_gates']} gate-instances")
print(f"enabling depth used: " + ", ".join(f"{d}:{n}" for d, n in sorted(depth_hist.items())))
print(f"enabling gates per solved cube: mean "
      f"{sum(len(p.get('req', ())) for p in plans if p['status']=='ok') / max(1, stat['solved']):.1f}")

OK = [p for p in plans if p["status"] == "ok"]
if os.environ.get("SOLVE_ONLY"):
    # depth sweep / sanity: stop before the dump index (the expensive half).
    json.dump({"tag": TAG, "stat": dict(stat),
               "depth_hist": {str(k): v for k, v in depth_hist.items()},
               "gates": [len(p.get("req") or {}) for p in OK]},
              open(os.path.join(HERE, f"_enable_solve_{TAG}.json"), "w"))
    print(f"SOLVE_ONLY: wrote _enable_solve_{TAG}.json; stopping before the index")
    sys.exit(0)

# ---------------------------------------------- 2. dump index (BITMASKS) ----
# The base search is O(witnesses x dumps) — 8 807 x 96 148 = 847 M iterations
# if a candidate is a Python object. It is not: every "which dumps evaluate e
# with outcome w" question is a BITMASK over the snapshot (96 148 bits = 12 kB
# per mask, ~400 masks = 5 MB), and the compatibility test is `&`. Per-dump
# path-condition dicts are never retained; the chosen base's alias map is
# recomputed by re-reading that ONE dump.
WANTED = set()
for p in OK:
    for x, _w in p["cube"]:
        WANTED.add(x)
        WANTED.add(_LEN.sub(r"SYM_LEN_\1", x))
    for g in p["req"]:
        WANTED.add(g)
        WANTED.add(_LEN.sub(r"SYM_LEN_\1", g))

_DL = os.environ.get("DUMP_LIST")
if _DL:
    _files = [l.strip() for l in open(_DL) if l.strip()]
    _files = sorted(f if os.path.isabs(f) else os.path.join(HERE, f) for f in _files)
    print(f"DUMP_LIST {_DL}: {len(_files)} dumps")
else:
    import glob
    _files = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    print(f"corpus: {len(_files)} dumps")

paths, variants = [], []
pol = {}                       # (expr, outcome) -> bitmask
vmask = {v: 0 for v in VARIANTS}
expr_variants = defaultdict(set)
t1 = time.time()
for i, fp in enumerate(_files):
    if i and i % 20000 == 0:
        print(f"  indexing [{i}/{len(_files)}] {time.time()-t1:.0f}s", flush=True)
    base = os.path.basename(fp)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), None)
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    canonicalize_ordinals(d)
    idx = len(paths)
    paths.append(fp)
    variants.append(v)
    if v:
        vmask[v] |= 1 << idx
    b = 1 << idx
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            ex = e["expr"]
            expr_variants[ex].add(v)
            if ex in WANTED:
                k = (ex, bool(e.get("taken")))
                pol[k] = pol.get(k, 0) | b
    del d
N = len(paths)
ev = {}
for (e, _w), m in pol.items():
    ev[e] = ev.get(e, 0) | m
print(f"indexed {N} dumps, {len(expr_variants)} exprs, {len(WANTED)} wanted, "
      f"{len(pol)} polarity masks ({time.time()-t1:.0f}s)")
fixed_to_orig = {_LEN.sub(r"SYM_LEN_\1", e): e for e in expr_variants}

_seed_cache, _vars_cache, _inv_cache = {}, {}, {}


def _load_seeds(path):
    try:
        return json.load(open(path)).get("concolic_seeds") or {}
    except Exception:
        return {}


def seeds_of(path):
    s = _seed_cache.get(path)
    if s is None:
        s = _seed_cache[path] = _load_seeds(path)
    return s


def inv_of(path):
    """canonical -> [ordinals] for ONE dump, recomputed on demand."""
    iv = _inv_cache.get(path)
    if iv is None:
        iv = {}
        try:
            d = json.load(open(path))
            for _o, _c in canonicalize_ordinals(d).items():
                iv.setdefault(_c, []).append(_o)
        except Exception:
            pass
        _inv_cache[path] = iv
    return iv


def base_var_value(path, name):
    vm = _vars_cache.get(path)
    if vm is None:
        try:
            vm = {v.get("name"): v.get("value")
                  for v in (json.load(open(path)).get("symbolic_vars") or ())}
        except Exception:
            vm = {}
        _vars_cache[path] = vm
    return vm.get(name)


_pc_cache = {}


def popcount(m):
    v = _pc_cache.get(m)
    if v is None:
        v = _pc_cache[m] = bin(m).count("1")
    return v


def bits(mask, cap=64):
    """Up to `cap` set-bit indices of `mask`, lowest first."""
    out = []
    while mask and len(out) < cap:
        lb = mask & -mask
        out.append(lb.bit_length() - 1)
        mask ^= lb
    return out


# ---------------------------------------------- 3. compatible base + seed ---
# MEMORY: at MMC=16 a pass names up to ~16 700 witnesses, and a seed dict is
# ~270 keys (~30 kB in Python). Accumulating them per variant is >1 GB before
# anything is written, on a box shared with another endpoint. So the per-variant
# files are STREAMED, and the duplicate check keys on a 16-byte digest rather
# than on the serialised dict.
import hashlib as _hl
_fh = {v: open(os.path.join(HERE, f"_enableR_{v}.json"), "w") for v in VARIANTS}
for _v in VARIANTS:
    _fh[_v].write("[")
per_count = {v: 0 for v in VARIANTS}
seen_seed = {v: set() for v in VARIANTS}
bstat = defaultdict(int)
compat_hist = defaultdict(int)
gates_hist = defaultdict(int)
hit_hist = defaultdict(int)
ALLMASK = (1 << N) - 1
emitted = 0
t2 = time.time()
for pi, p in enumerate(OK):
    if pi and pi % 1000 == 0:
        print(f"  basing [{pi}/{len(OK)}] emitted={emitted} {time.time()-t2:.0f}s", flush=True)
    cube, req, model = p["cube"], p["req"], p["model"]
    origs = []
    for x, w in cube:
        o = fixed_to_orig.get(x) or (x if x in expr_variants else None)
        if o:
            origs.append((o, w))
    if not origs:
        bstat["no_expr"] += 1
        continue
    reqo = {}
    for g, w in req.items():
        o = fixed_to_orig.get(g) or (g if g in expr_variants else None)
        if o:
            reqo[o] = w
    vs = None
    for o, _w in origs:
        s_ = expr_variants[o]
        vs = set(s_) if vs is None else (vs & s_)
    vs = vs or set(VARIANTS)

    unseed, forceseed = set(), set()
    if UNSEED:
        for _o, _w in origs:
            _v = selfcmp_var(_o)
            if _v:
                (forceseed if _w else unseed).add(_v)

    # §13.1's COMPATIBILITY TEST, per witness, as a mask intersection.
    # (i) the base must EVALUATE every member — that is what "these decisions
    # are co-evaluable in this context" means, and it is the property the
    # reachability split measured; (ii) among those, take the ones that also
    # AGREE with the model on as many ENABLING GATES as possible, greedily
    # (an exact maximum would be a set-cover; the greedy pass is one `&` per
    # gate and never leaves the compatible set); (iii) prefer the variants
    # that record the whole cube. Richness is no longer a criterion.
    # (i) MEMBERS. Intersect the "evaluates e" masks, rarest first, keeping
    # the intersection non-empty. A base that survives every member is a
    # FULLY compatible context — the run §13.3 says exists for a REACHABLE
    # cube. When one does not survive, the greedy prefix is kept and the
    # shortfall RECORDED (`hit` < `len(origs)`): that is the seeder's own
    # view of the multi-gate-foreclosed residue, and it is what names the
    # members no observed walk carries alongside the rest.
    order = sorted(origs, key=lambda ow: popcount(ev.get(ow[0], 0)))
    cand, hit = ALLMASK, 0
    for o, _w in order:
        nxt = cand & ev.get(o, 0)
        if nxt:
            cand, hit = nxt, hit + 1
    if not cand:
        bstat["no_compatible_base"] += 1
        p["status"] = "no_compatible_base"
        continue
    p["members"] = len(origs)
    p["member_hit"] = hit
    if hit < len(origs):
        bstat["partial_base"] += 1
    else:
        bstat["full_base"] += 1
    hit_hist[len(origs) - hit] += 1
    agree = 0
    for g, w in reqo.items():
        nxt = cand & pol.get((g, w), 0)
        if nxt:
            cand, agree = nxt, agree + 1
    vm = 0
    for v in vs:
        vm |= vmask.get(v, 0)
    if cand & vm:
        cand &= vm
    # UNSEED needs a base that does not itself seed V (the child is the base's
    # seeds verbatim plus the overlay, so a base carrying V hands it back).
    pick = None
    for bi in bits(cand, cap=int(os.environ.get("BASE_PROBE", "40"))):
        if unseed and any(u in seeds_of(paths[bi]) for u in unseed):
            continue
        pick = bi
        break
    if pick is None:
        bstat["no_unseed_clean_base"] += 1
        p["status"] = "no_unseed_clean_base"
        continue
    compat_hist[agree] += 1
    gates_hist[len(reqo)] += 1
    base_path, base_v = paths[pick], variants[pick]
    base_inv = inv_of(base_path)
    p["base"] = os.path.basename(base_path)
    p["base_agree"] = agree
    p["base_gates"] = len(reqo)

    # Overlay ONLY the variables the cube's members and the enabling gates
    # mention — never the whole model (§12.10: its 0-defaults on every list
    # length foreclose the decisions the cube is about).
    want_vars = set()
    for e in [o for o, _w in origs] + list(reqo):
        for tok in _IDENT.findall(e):
            if tok in KNOWN or tok.startswith("SYM_"):
                want_vars.add(tok)
                if tok.startswith("SYM_LEN_"):
                    want_vars.add("len(" + tok[8:] + ")")
    # `V__prior` has NO runtime variable — it is `coverage_report`'s load-time
    # repair for `call_interceptor.rb:142-144` naming both operands of a
    # self-compare alike (§12.5). Writing it into a seed dict is INERT, and
    # measured: it is the single most-often "never evaluated" key of DR5's own
    # round (200/200 runs). Dropped, so the round's seed-key audit measures
    # keys that could have been evaluated.
    overlay = {unfix(k): v for k, v in model.items()
               if (k in want_vars or unfix(k) in want_vars)
               and not k.endswith("__prior")}
    p["overlay_keys"] = len(overlay)

    seed = dict(seeds_of(base_path))
    if unseed or forceseed:
        for _v in unseed:
            seed.pop(_v, None)
        for _v in forceseed:
            if _v not in seed:
                seed[_v] = to_seed(model.get(_v, 0))
    _canon_re = re.compile(
        "(" + "|".join(sorted(map(re.escape, base_inv), key=len, reverse=True))
        + ")(?![0-9])") if base_inv else None
    for k, val in overlay.items():
        if "SYM_RESULT_" in k and re.search(r"_(?:records|to_ary)_[a-z_]+_[0-9a-f]{8}", k):
            if _canon_re is None or not _canon_re.search(k):
                bstat["skipped_no_ordinal"] += 1
                continue
            mm = _canon_re.search(k)
            for _ordn in base_inv[mm.group(1)]:
                seed[k[:mm.start()] + _ordn + k[mm.end():]] = val
        else:
            seed[k] = val
    for _v in unseed:
        seed.pop(_v, None)
        _v0 = base_var_value(base_path, _v)
        if _v0 is None:
            continue
        for _o, _w in origs:
            if selfcmp_var(_o) or _v not in _o:
                continue
            _mm = re.match(r"^\((SYM_[A-Za-z0-9_]+) == (SYM_[A-Za-z0-9_]+)\)$", _o.strip())
            if not _mm:
                continue
            _x = _mm.group(2) if _mm.group(1) == _v else _mm.group(1)
            if _x == _v:
                continue
            _tv = to_seed(_v0)
            seed[_x] = _tv if _w else (
                (_tv + 1) if isinstance(_tv, int) and not isinstance(_tv, bool)
                else "concolic_other")
    if not seed:
        bstat["empty_seed"] += 1
        continue
    # ONE_VARIANT (default under TARGETS): the base was chosen BECAUSE its
    # variant walks every member, so that variant is where the cube can be
    # realised. Emitting the same seed for every variant in `vs` (what
    # _demand_root.py did, and what DR3/DR5's per-run rates were measured
    # over) multiplies runs without multiplying witnesses; the owner's
    # instruction is one base, one seed, per remaining cube, so closed/run is
    # read against one run per target.
    if ONE_VARIANT and base_v:
        targets = [base_v]
    else:
        targets = sorted(vs) if vs else [base_v]
        if base_v and base_v not in targets:
            targets.append(base_v)
    blob = json.dumps(seed, sort_keys=True)
    key = _hl.blake2b(blob.encode(), digest_size=16).digest()
    got = False
    for v in targets:
        if v is None or key in seen_seed[v]:
            continue
        seen_seed[v].add(key)
        if per_count[v]:
            _fh[v].write(",")
        _fh[v].write(blob)
        per_count[v] += 1
        got = True
    emitted += 1 if got else 0
    bstat["dup_seed"] += 0 if got else 1
    # the base's own seed dict is no longer needed; the cache exists only to
    # avoid re-reading a base picked twice in a row.
    if len(_seed_cache) > 4000:
        _seed_cache.clear()
        _vars_cache.clear()
        _inv_cache.clear()

for v in VARIANTS:
    _fh[v].write("]")
    _fh[v].close()
    out = os.path.join(HERE, f"_enableR_{v}.json")
    if not per_count[v]:
        os.remove(out)
    print(f"{v}: {per_count[v]} enabling-rooted seed dicts")
print(f"witnesses emitted: {emitted} of {len(OK)} solved  ({time.time()-t2:.0f}s)")
print(f"base stats: {dict(bstat)}")
print("enabling gates per cube: " +
      ", ".join(f"{k}:{v}" for k, v in sorted(gates_hist.items())))
print("base AGREEMENT with the model on those gates: " +
      ", ".join(f"{k}:{v}" for k, v in sorted(compat_hist.items())))
print("cube MEMBERS the chosen base does NOT evaluate (0 = fully compatible): " +
      ", ".join(f"{k}:{v}" for k, v in sorted(hit_hist.items())))
json.dump({"tag": TAG, "summary_in": os.environ.get("SUMMARY_IN"),
           "targets": _TARGETS, "skipped_multigate": skipped_unreach_group,
           "forecl": F.get("dump_list"), "dump_list": _DL, "plans": plans,
           "stat": dict(stat), "bstat": dict(bstat),
           "compat_hist": dict(compat_hist), "gates_hist": dict(gates_hist),
           "hit_hist": dict(hit_hist)},
          open(os.path.join(HERE, f"_enable_plan_{TAG}.json"), "w"))
print(f"wrote _enable_plan_{TAG}.json")
