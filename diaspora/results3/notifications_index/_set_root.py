#!/usr/bin/env python3
"""PER-LEAF-GROUP OVERLAY seeding — thousands of seeds in seconds, no per-cube Z3.

Owner ruling (2026-09-11): "stop solving one Z3 model per cube — use the graph
structure systematically... Emit a seed per cube by OVERLAY, no solver."

WHY THE SOLVER IS NOT NEEDED. Everything that needs deciding is per LEAF GROUP,
not per cube:

* Satisfiability is already established — `_exact_enum.py` listed these cubes
  as satisfiable; re-proving it per cube is what made `_enable_root.py` take
  2 756 s for 22 562 cubes (and produced a mean of 221 constrained gates per
  cube, i.e. an over-constrained near-bulk seed).
* Within-set foreclosure consistency is already encoded in the cube: a cube IS
  a leaf of the pruned tree, so its members are exactly the decisions NOT
  foreclosed under its own gate outcomes.
* The OUTSIDE-set enabling gates are a property of the leaf group, and a base
  run that walked ALL of the group's members under compatible gates already
  satisfies every one of them — that run is the witness that the group is
  jointly reachable, and for a REACHABLE group §13.3 guarantees it exists.

So: pick the base once per group (§13.1's compatibility test), then overlay
each cube's member outcomes onto that base's seeds. Values come from the
base's own minted values wherever the base already walks the demanded side,
and otherwise from the expression's syntax — every active expression on this
endpoint is one of `(V == True)`, `(V == k)`, `(V != k)`, `(V > k)`,
`(V <= k)`, `(V == 'str')` or `(V == V2)` (408 of 408 checked), all of which
invert directly. A cube whose members cannot all be derived that way is an
EXCEPTION and is counted (and, with SOLVE_EXCEPTIONS=1, handed to a Z3 pool).

inputs   TARGETS=_remaining_<tag>.jsonl   DUMP_LIST=<pruned snapshot>
         FORECL_IN=_forecl.json (for the outside-gate verification only)
outputs  _setR_<variant>.json, _set_plan_<TAG>.json
env      BASES_PER_GROUP (3)  UNSEED_SELFCMP (1)  TAG
"""
import json, os, re, sys, time
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals   # noqa: E402

VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
NBASE = int(os.environ.get("BASES_PER_GROUP", "3"))
UNSEED = os.environ.get("UNSEED_SELFCMP", "1") != "0"
TAG = os.environ.get("TAG", "S1")
INCLUDE_MG = os.environ.get("INCLUDE_MULTIGATE", "0") == "1"

_UNREACHABLE = {
    ("(SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_username == '')", True),
}
_SELFCMP = re.compile(r"^\((SYM_[A-Za-z0-9_]+) == \1__prior\)$")
_CMP2 = re.compile(r"^\((SYM_[A-Za-z0-9_]+) (==|!=) (SYM_[A-Za-z0-9_]+)\)$")
_LEN = re.compile(r"len\(([^()]+)\)")
_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

# --- expression inversion ---------------------------------------------------
_EQ_TRUE = re.compile(r"^\((SYM_[A-Za-z0-9_]+) == True\)$")
_EQ_INT = re.compile(r"^\((SYM_[A-Za-z0-9_]+) == (-?\d+)\)$")
_NE_INT = re.compile(r"^\((SYM_[A-Za-z0-9_]+) != (-?\d+)\)$")
_GT_INT = re.compile(r"^\((SYM_[A-Za-z0-9_]+) > (-?\d+)\)$")
_LE_INT = re.compile(r"^\((SYM_[A-Za-z0-9_]+) <= (-?\d+)\)$")
_EQ_STR = re.compile(r"^\((SYM_[A-Za-z0-9_]+) == (?:StringVal\()?'((?:[^'\\]|\\.)*)'\)?\)$")


def invert(expr, want, basev):
    """(variable, value) realising `expr == want`, preferring a value the BASE
    already has. Returns None when the shape is not invertible."""
    m = _EQ_TRUE.match(expr)
    if m:
        return m.group(1), bool(want)
    m = _EQ_INT.match(expr)
    if m:
        v, k = m.group(1), int(m.group(2))
        if want:
            return v, k
        return v, (basev if isinstance(basev, int) and not isinstance(basev, bool)
                   and basev != k else k + 1)
    m = _NE_INT.match(expr)
    if m:
        v, k = m.group(1), int(m.group(2))
        if not want:
            return v, k
        return v, (basev if isinstance(basev, int) and not isinstance(basev, bool)
                   and basev != k else k + 1)
    m = _GT_INT.match(expr)
    if m:
        v, k = m.group(1), int(m.group(2))
        if want:
            # keep the base's own length when it already exceeds k — a bigger
            # list than needed forecloses nothing
            return v, (basev if isinstance(basev, int) and not isinstance(basev, bool)
                       and basev > k else k + 1)
        # NOT (> k)  ->  k, never 0: a 0-length list would foreclose the very
        # row decisions the cube is about (§12.10).
        return v, (basev if isinstance(basev, int) and not isinstance(basev, bool)
                   and 0 <= basev <= k else k)
    m = _LE_INT.match(expr)
    if m:
        v, k = m.group(1), int(m.group(2))
        if want:
            return v, (basev if isinstance(basev, int) and not isinstance(basev, bool)
                       and 0 <= basev <= k else k)
        return v, k + 1
    m = _EQ_STR.match(expr)
    if m:
        v, s = m.group(1), m.group(2)
        if want:
            return v, s
        return v, (basev if isinstance(basev, str) and basev != s else "concolic_other")
    return None


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


def selfcmp_var(e):
    m = _SELFCMP.match(e.strip())
    return m.group(1) if m else None


# ------------------------------------------------------------- 1. targets --
T = os.environ["TARGETS"]
groups = defaultdict(list)          # (set, members frozenset) -> [cube dicts]
n_unreach = n_skip = n_mg_kept = 0
for line in open(T):
    if not line.strip():
        continue
    r = json.loads(line)
    if not r.get("reachable"):
        n_unreach += 1
        # RULING 2026-09-11 (1c): the cubes the leaf-group test calls
        # MULTI-GATE-FORECLOSED are DRIVING BACKLOG, not a declaration — the
        # corpus already produces the "find_by_1 hit ∧ find_by_2 miss" shape
        # they turn on, in 38 of 771 co-evaluating runs (§16.3). The test says
        # "no observed profile walked exactly these members under exactly this
        # gate prefix", which is a statement about the corpus, not about the
        # app; 128 of them dissolved under S1 alone. With INCLUDE_MULTIGATE=1
        # they are seeded like any other target — the base is then the best
        # PARTIAL match (the greedy prefix), which is exactly what a cube with
        # no fully compatible walk needs.
        if not INCLUDE_MG:
            continue
        n_mg_kept += 1
    full = dict(r.get("pre") or {})
    full.update(r.get("asg") or {})
    if any((e, v) in _UNREACHABLE for e, v in full.items()):
        n_skip += 1
        continue
    groups[(r["set"], frozenset(full))].append(full)
ncubes = sum(len(v) for v in groups.values())
print(f"TARGETS {T}: {ncubes} REACHABLE cubes in {len(groups)} leaf groups; "
      f"{n_unreach} MULTI-GATE-FORECLOSED "
      f"({'DRIVEN too, ruling 1c' if INCLUDE_MG else 'skipped, declared residue §13.3'}"
      f"{f': {n_mg_kept} kept' if INCLUDE_MG else ''}); "
      f"{n_skip} environmentally unreachable skipped (§7.7)", flush=True)

# The checker/enumerator name lengths `SYM_LEN_X`; the DUMPS name them
# `len(X)` (coverage_report.fix_len_names converts one to the other at load).
# WANTED must carry the DUMP-side spelling or the length decisions — which is
# most of the gating on this endpoint — are never indexed at all.
_UNLEN = re.compile(r"SYM_LEN_([A-Za-z0-9_]+)")
WANTED = set()
for (_s, mem) in groups:
    for e in mem:
        WANTED.add(e)
        WANTED.add(_UNLEN.sub(r"len(\1)", e))

# --------------------------------------------------------- 2. dump index ---
_files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()]
_files = sorted(f if os.path.isabs(f) else os.path.join(HERE, f) for f in _files)
print(f"DUMP_LIST: {len(_files)} dumps", flush=True)
paths, variants = [], []
pol, ev = {}, {}
expr_variants = defaultdict(set)
t1 = time.time()
for i, fp in enumerate(_files):
    if i and i % 20000 == 0:
        print(f"  indexing [{i}/{len(_files)}] {time.time()-t1:.0f}s", flush=True)
    b = os.path.basename(fp)
    v = next((x for x in VARIANTS if b.startswith("dump_" + x)), None)
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    canonicalize_ordinals(d)
    idx = len(paths)
    paths.append(fp); variants.append(v)
    bit = 1 << idx
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            ex = e["expr"]
            expr_variants[ex].add(v)
            if ex in WANTED:
                k = (ex, bool(e.get("taken")))
                pol[k] = pol.get(k, 0) | bit
                ev[ex] = ev.get(ex, 0) | bit
    del d
print(f"indexed {len(paths)} dumps, {len(pol)} polarity masks "
      f"({time.time()-t1:.0f}s)", flush=True)
fixed_to_orig = {_LEN.sub(r"SYM_LEN_\1", e): e for e in expr_variants}

_sc, _vc, _ic = {}, {}, {}


def seeds_of(p):
    s = _sc.get(p)
    if s is None:
        try:
            s = json.load(open(p)).get("concolic_seeds") or {}
        except Exception:
            s = {}
        _sc[p] = s
    return s


def vars_of(p):
    s = _vc.get(p)
    if s is None:
        try:
            s = {x.get("name"): x.get("value")
                 for x in (json.load(open(p)).get("symbolic_vars") or ())}
        except Exception:
            s = {}
        _vc[p] = s
    return s


def inv_of(p):
    s = _ic.get(p)
    if s is None:
        s = {}
        try:
            for o, c in canonicalize_ordinals(json.load(open(p))).items():
                s.setdefault(c, []).append(o)
        except Exception:
            pass
        _ic[p] = s
    return s


def bits(mask, cap):
    out = []
    while mask and len(out) < cap:
        lb = mask & -mask
        out.append(lb.bit_length() - 1)
        mask ^= lb
    return out


# ------------------------------------- 3. one base per group, then overlay --
fh = {v: open(os.path.join(HERE, f"_setR_{v}.json"), "w") for v in VARIANTS}
for v in VARIANTS:
    fh[v].write("[")
cnt = {v: 0 for v in VARIANTS}
seen = {v: set() for v in VARIANTS}
import hashlib as _hl
stat = defaultdict(int)
flip_hist = defaultdict(int)
plan = []
t2 = time.time()
for (sid, mem), cubes in groups.items():
    origs = []
    for e in mem:
        o = fixed_to_orig.get(e) or (e if e in expr_variants else None)
        if o:
            origs.append((e, o))
    if len(origs) < len(mem):
        stat["group_expr_missing"] += 1
    # §13.1's compatibility test: a run that evaluated every member of this
    # leaf group. For a REACHABLE group §13.3 guarantees one exists. Rarest
    # member first, and if some member cannot be kept the greedy PREFIX is
    # used and the shortfall recorded — a group never silently yields nothing.
    order = sorted(origs, key=lambda eo: bin(ev.get(eo[1], 0)).count("1"))
    cand, hit = (1 << len(paths)) - 1, 0
    for _e, o in order:
        nxt = cand & ev.get(o, 0)
        if nxt:
            cand, hit = nxt, hit + 1
    if not cand:
        stat["group_no_compatible_base"] += 1
        stat["cubes_lost_no_base"] += len(cubes)
        continue
    if hit < len(origs):
        stat["group_partial_base"] += 1
        stat["members_unmatched"] += len(origs) - hit
    else:
        stat["group_full_base"] += 1
    stat["group_with_base"] += 1
    bidx = bits(cand, NBASE)
    for full in cubes:
        # the base among this group's candidates that already agrees most
        best, bestn = None, -1
        for bi in bidx:
            n = sum(1 for e, o in origs
                    if (pol.get((o, full[e]), 0) >> bi) & 1)
            if n > bestn:
                best, bestn = bi, n
        bp, bv = paths[best], variants[best]
        bvars, bseeds, binv = vars_of(bp), seeds_of(bp), inv_of(bp)
        flips = len(origs) - bestn
        flip_hist[flips] += 1
        unseed, force = set(), set()
        if UNSEED:
            for e, o in origs:
                sv = selfcmp_var(e)
                if sv:
                    (force if full[e] else unseed).add(sv)
        seed = dict(bseeds)
        for sv in unseed:
            seed.pop(sv, None)
        overlay, bad = {}, False
        for e, o in origs:
            if (pol.get((o, full[e]), 0) >> best) & 1:
                continue                       # the base already walks it
            # INVERT ON THE CHECKER-SIDE SPELLING `e`. `o` is the DUMP-side
            # name, which spells a length `len(X)` and matches none of the
            # inversion patterns — inverting `o` made 20 554 of 22 562 cubes
            # look "not invertible" when 358 of the 368 member expressions
            # invert directly and the other 10 are cross-compares handled just
            # below. The variable the inversion yields is `SYM_LEN_X`, which
            # the seed writer converts back to the runtime's `len(X)`.
            if selfcmp_var(e):
                continue                       # handled by the UNSEED rule
            m2 = _CMP2.match(e)
            if m2:                             # cross-variable compare
                a, op, b2 = m2.group(1), m2.group(2), m2.group(3)
                av = bvars.get(a)
                if av is None:
                    av = bvars.get(b2)
                want_eq = (full[e] == (op == "=="))
                if av is None:
                    # Neither operand was minted by this base, so there is no
                    # observed value to anchor on. The compare is still
                    # realisable without a solver: an identity compare only
                    # needs the two operands to AGREE (or to differ), so seed
                    # BOTH with a common literal. Measured: this is what the
                    # 3 175 "needs a solver" cubes of S2 were — the residue
                    # after S1 is enriched in exactly the identity compares
                    # whose operands the base never minted.
                    stat["cmp_anchorless"] += 1
                    if want_eq:
                        overlay[a] = overlay[b2] = 1
                    else:
                        overlay[a] = 1
                        overlay[b2] = 2
                    continue
                sv_ = to_seed(av)
                overlay[a] = sv_
                overlay[b2] = (sv_ if want_eq else
                               (sv_ + 1 if isinstance(sv_, int)
                                and not isinstance(sv_, bool)
                                else "concolic_other"))
                continue
            _v0 = _IDENT.findall(e)[0]
            _bv = bvars.get(_v0)
            if _bv is None and _v0.startswith("SYM_LEN_"):
                _bv = bvars.get("len(" + _v0[8:] + ")")
            r = invert(e, full[e], _bv)
            if r is None:
                bad = True; break
            overlay[r[0]] = to_seed(r[1])
        if bad:
            stat["cube_not_invertible"] += 1
            continue
        canon = re.compile("(" + "|".join(sorted(map(re.escape, binv),
                                                key=len, reverse=True)) + ")(?![0-9])") \
            if binv else None
        for k, val in overlay.items():
            kk = f"len({k[8:]})" if k.startswith("SYM_LEN_") else k
            if "SYM_RESULT_" in kk and re.search(r"_(?:records|to_ary)_[a-z_]+_[0-9a-f]{8}", kk):
                if canon is None or not canon.search(kk):
                    stat["skipped_no_ordinal"] += 1
                    continue
                mm = canon.search(kk)
                for ordn in binv[mm.group(1)]:
                    seed[kk[:mm.start()] + ordn + kk[mm.end():]] = val
            else:
                seed[kk] = val
        for sv in force:
            if sv not in seed:
                seed[sv] = to_seed(bvars.get(sv, 0))
        for sv in unseed:
            seed.pop(sv, None)
        if not seed:
            stat["empty_seed"] += 1
            continue
        blob = json.dumps(seed, sort_keys=True)
        key = _hl.blake2b(blob.encode(), digest_size=16).digest()
        tv = bv or "html_plain"
        if key in seen[tv]:
            stat["dup_seed"] += 1
            continue
        seen[tv].add(key)
        if cnt[tv]:
            fh[tv].write(",")
        fh[tv].write(blob)
        cnt[tv] += 1
        stat["emitted"] += 1
    if len(_sc) > 6000:
        _sc.clear(); _vc.clear(); _ic.clear()

for v in VARIANTS:
    fh[v].write("]"); fh[v].close()
    if not cnt[v]:
        os.remove(os.path.join(HERE, f"_setR_{v}.json"))
    print(f"{v}: {cnt[v]} overlay seed dicts")
el = time.time() - t2
print(f"\nemitted {stat['emitted']} seeds from {ncubes} cubes in {el:.1f}s "
      f"= {stat['emitted']/max(el,1e-9):.0f} seeds/s (index excluded)")
print(f"leaf groups FULLY compatible: {stat['group_full_base']}, partial: "
      f"{stat['group_partial_base']} (unmatched members {stat['members_unmatched']})")
print(f"leaf groups with a compatible base: {stat['group_with_base']} of {len(groups)}"
      f"  (no base: {stat['group_no_compatible_base']}, "
      f"costing {stat['cubes_lost_no_base']} cubes)")
print(f"cubes needing a SOLVER (not syntactically invertible): {stat['cube_not_invertible']}")
print(f"identity compares seeded with a common literal (no minted anchor): "
      f"{stat['cmp_anchorless']}")
print(f"other: dup={stat['dup_seed']} no_ordinal={stat['skipped_no_ordinal']} "
      f"empty={stat['empty_seed']}")
print("members the base had to be FLIPPED on, per cube: " +
      ", ".join(f"{k}:{v}" for k, v in sorted(flip_hist.items())[:12]))
json.dump({"tag": TAG, "targets": T, "cubes": ncubes, "groups": len(groups),
           "stat": dict(stat), "flip_hist": dict(flip_hist),
           "seeds_per_s": stat['emitted'] / max(el, 1e-9),
           "per_variant": cnt},
          open(os.path.join(HERE, f"_set_plan_{TAG}.json"), "w"), indent=1)
print(f"wrote _set_plan_{TAG}.json")
