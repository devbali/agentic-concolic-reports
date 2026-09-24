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
# P0 (2026-09-08): the checker's exprs are CANONICAL (statement-named) — see
# coverage_report.canonicalize_ordinals. Dumps are indexed after the same
# canonicalization, and a demanded `len(<canonical>_rows)` seed is mapped
# BACK to the base dump's own ordinal (the runtime seeds by ordinal). A
# demanded length whose statement the base dump never issued has no ordinal
# there and is SKIPPED (counted) — seeding it by a guessed ordinal is exactly
# how 164 `records_11` seeds were inert in round D1.
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals  # noqa: E402
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")

summary = json.load(open(os.path.join(HERE, "coverage_summary.json")))
missing = [m for m in summary.get("missing", []) if not m.get("untracked")]
# ONLY_SELFCMP=1 (2026-09-10, §12.11): restrict the round to the witnesses whose
# cube constrains the `(V == V__prior)` self-compare, so the SELF-COMPARE rule's
# conversion rate is attributable to the rule and not diluted by 8 000 other
# witnesses. Its falsifier is stated in the campaign: if these convert at DR4's
# 0.014/run the presence-control reading is wrong.
if os.environ.get("ONLY_SELFCMP"):
    _b = len(missing)
    missing = [m for m in missing
               if "__prior)" in (m.get("node_constraint") or "")]
    print(f"ONLY_SELFCMP: {len(missing)} of {_b} witnesses constrain a self-compare")
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
_DL = os.environ.get("DUMP_LIST")
if _DL:
    _files = [l.strip() for l in open(_DL) if l.strip()]
    _files = sorted(f if os.path.isabs(f) else os.path.join(HERE, f) for f in _files)
    print(f"DUMP_LIST {_DL}: {len(_files)} dumps (fixed snapshot — the SAME list "
          f"the pass measured, so a root is built from a dump the witness saw)")
else:
    _files = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
for p in _files:
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), None)
    try:
        d = json.load(open(p))
    except Exception:
        continue
    amap = canonicalize_ordinals(d)          # exprs now canonical, like the checker's
    # canonical -> ALL of this dump's ordinals backing it.
    # BUG FIXED 2026-09-09: this was `{c: o for o, c in amap.items()}`, which
    # inverts a MANY-to-one map by keeping whichever ordinal came LAST. The
    # alias map is many-to-one BY DESIGN (8 ordinals -> one `aspects`), so the
    # seed landed on one arbitrary ordinal while the path could evaluate a
    # different one — the demanded variable then took its default and the run
    # CONTRADICTED the seed. Measured before the fix: 13 423 honoured,
    # **6 656 contradicted** (25% of evaluated seeds), 6 794 never evaluated.
    # Seeding EVERY ordinal that backs the canonical makes the demand hold
    # whichever one the path takes.
    inv = {}
    for _o, _c in amap.items():
        inv.setdefault(_c, []).append(_o)
    pcs = {}
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            ex = e["expr"]
            expr_variants[ex].add(v)
            if ex in _WANTED:
                pcs[ex] = bool(e.get("taken"))
    # MEMORY (2026-09-10): keep the PATH, not the seeds. v3 seed dicts carry
    # ~270 keys; holding them for 125 000 dumps is several GB and OOMs the
    # round. Only the chosen bases' seeds are ever needed, so they are loaded
    # lazily below (memoised).
    dumps.append((v, p, pcs, inv))
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


# UNREACHABLE OUTCOMES (2026-09-10, _COMPLETION_CAMPAIGN §7.4/§7.7). Three
# branch outcomes cannot be observed in this environment:
#   T1/T2  taking `Core__ClassMethods_find_by_1_{not_found,profile_not_found}`
#          enters `Discovery#fetch_and_save` and SIGSEGVs the JVM in libcurl
#          BEFORE the dump is written — 37/37 toxic seeds, 0/25.6 % control;
#   T10    `devise_user_first_1_username == ''` is foreclosed by
#          `user_profile_path` two lines above the compare (routes.rb:189).
# A demand cube that assigns one of them is not drivable, so it is SKIPPED and
# COUNTED rather than turned into a seed that kills the runner. Every other
# cube pins the two discovery booleans OFF, which is what makes a demand round
# abort-free (measured: 0 aborts in 157 rooted runs).
_D1 = "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found"
_D2 = "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_profile_not_found"
# 2026-09-10 (C8): T1/T2 are OFF this list — `targets.rb` §5h-bis now walls
# `Discovery#fetch_and_save` in its RAISING form, so the discovery arm no
# longer aborts the JVM and those cubes ARE drivable. Only T10 remains, and it
# is a declared `OneSideUntracked` so the checker will not demand it either.
_UNREACHABLE = {
    ("(SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_username == '')", True),
}

# SELF-COMPARE: the decision is set by the seed key's PRESENCE, not its value
# (campaign §12.5, 2026-09-10). `coverage_report.split_self_compare` renames the
# RIGHT operand of `(V == V)` to `V__prior`, so a cube can demand either side of
# `gon_helper.rb:6`. But `V__prior` has NO runtime variable — it is a load-time
# repair for `call_interceptor.rb:142-144` naming both operands alike — so
# writing `V__prior` into a seed dict is inert, which is why a demand round can
# never realise these cubes.
#
# What DOES control the decision is whether `V` ITSELF is present in the seed
# dict. MEASURED, not argued:
#     V present in the seed dict  ->  TAKEN     (358 runs, no exception)
#     V absent                    ->  NOT TAKEN (187 runs, no exception)
# over a 20 000-dump sample of the 227 973-dump corpus, with 0 runs recording
# both sides in one walk; and by a control-vs-flip differential on ONE base
# (`dump_html_plain_dse0107_D13htm`, campaign §12.5): the same seed dict with
# that ONE key removed goes taken x2 -> not_taken x3, rc=0 both sides.
# The PRESENCE is what is measured. The natural mechanism is that both operands
# consult `seed_for("V", default)`, so a seeded V answers both call ordinals
# alike while an unseeded one does not -- but note the differential minted
# value is 0 on BOTH sides, so `symbolic_vars` (one entry per NAME) does not
# show the second operand and that mechanism is inference, not measurement.
#
# So the rule is: demand TAKEN -> make sure V is in the seed dict; demand
# NOT TAKEN -> DELETE V from it. And when V is deleted, any OTHER conjunct
# comparing V to a second variable must be satisfied by moving that SECOND
# variable to V's unseeded value, because V is no longer ours to set.
_SELFCMP = re.compile(r"^\((SYM_[A-Za-z0-9_]+) == \1__prior\)$")
UNSEED = os.environ.get("UNSEED_SELFCMP", "1") != "0"


def selfcmp_var(expr):
    m = _SELFCMP.match(expr.strip())
    return m.group(1) if m else None


_vars_cache = {}


def base_var_value(path, name):
    """The value the BASE dump minted for `name` (its unseeded value, when the
    base did not seed it). Loaded lazily and memoised, like the base seeds."""
    vm = _vars_cache.get(path)
    if vm is None:
        try:
            vm = {v.get("name"): v.get("value")
                  for v in (json.load(open(path)).get("symbolic_vars") or ())}
        except Exception:
            vm = {}
        _vars_cache[path] = vm
    return vm.get(name)


NBASES = int(os.environ.get("DEMAND_BASES", "3"))
_seed_cache = {}


def _load_seeds(path):
    try:
        return json.load(open(path)).get("concolic_seeds") or {}
    except Exception:
        return {}
per_variant = {v: [] for v in VARIANTS}
seen = {v: set() for v in VARIANTS}
no_base = 0
skipped_no_ordinal = 0
skipped_unreachable = 0
unseeded_cubes = 0
unseed_no_clean_base = 0
for m in missing:
    cj = conjuncts(m.get("node_constraint") or "")
    if any((x, w) in _UNREACHABLE for x, w in cj):
        skipped_unreachable += 1
        continue
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
    # Which variables must be ABSENT from the seed dict for this cube, and
    # which must be PRESENT (see the SELF-COMPARE note above).
    unseed, forceseed = set(), set()
    if UNSEED:
        for _o, _w in origs:
            _v = selfcmp_var(_o)
            if _v:
                (forceseed if _w else unseed).add(_v)
    want = set()
    for _o, _w in origs:
        for tok in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", _o):
            want.add(tok)
            if tok.startswith("SYM_LEN_"):
                want.add("len(" + tok[8:] + ")")
    demanded = {unfix(k): to_seed(v) for k, v in (m.get("concrete_values") or {}).items()
                if k in want or unfix(k) in want}
    # best base dumps: record the most of the combination's exprs; among ties
    # prefer ones whose polarities DIFFER from the demand (the "other polarity"
    # dump the coordinator asked for) and whose variant is in vs.
    #
    # NBASES (2026-09-10): ONE base per witness converts at ~18 % (measured:
    # DR3 drove 15 630 rooted seeds and took `remaining` 27 487 -> 24 590).
    # A cube can fail to realise because the ONE base chosen puts the
    # unconstrained dimensions somewhere the cube cannot live; a different base
    # with the same score often does not. Keeping the top NBASES bases per
    # witness multiplies the seeds per witness and is the cheapest lever there
    # is — a seed costs ~0.1 s of JRuby, a round costs a 2 h pass.
    # EARLY EXIT (2026-09-10): the base search is O(missing x dumps) and at
    # 5 871 witnesses x 153 252 dumps that is 900 M iterations. A dump that
    # records EVERY expr of the combination on the OPPOSITE polarity in a
    # variant the combination is recorded in is the best score obtainable, so
    # stop at it.
    # A cube that must UNSEED V is only realisable on a base that does not seed
    # V itself: the child is the base's seeds verbatim plus the demand, so a
    # base carrying V hands the child the TAKEN side no matter what we write.
    # That is a HARD requirement, so it outranks the polarity preference.
    _perfect = (1, len(origs), len(origs), 1) if unseed else (len(origs), len(origs), 1)
    cands = []
    best, bestscore = None, ((-1,) * (4 if unseed else 3))
    for (v, _path, pcs, _inv) in dumps:
        hit = sum(1 for o, _w in origs if o in pcs)
        if hit == 0:
            continue
        opp = sum(1 for o, w in origs if o in pcs and pcs[o] != w)
        score = (hit, opp, 1 if v in vs else 0)
        if unseed:
            clean = 0 if any(u in (_seed_cache.get(_path) or
                                   _seed_cache.setdefault(_path, _load_seeds(_path)))
                             for u in unseed) else 1
            score = (clean,) + score
        if score >= _perfect:
            cands.append((score, v, _path, _inv))
            if len(cands) >= NBASES:
                break
        elif score > bestscore:
            best, bestscore = (v, _path, _inv), score
    if not cands and best is not None:
        cands = [(bestscore,) + best]
    if not cands:
        no_base += 1
        continue
    for _score, base_v, _base_path, base_inv in cands:
        base_seeds = _seed_cache.get(_base_path)
        if base_seeds is None:
            try:
                base_seeds = json.load(open(_base_path)).get("concolic_seeds") or {}
            except Exception:
                base_seeds = {}
            _seed_cache[_base_path] = base_seeds
        seed = dict(base_seeds)
        # SELF-COMPARE, applied last-but-one so it wins over the model overlay.
        if unseed or forceseed:
            _clean = all(u not in base_seeds for u in unseed)
            if not _clean:
                unseed_no_clean_base += 1
            for _v in unseed:
                seed.pop(_v, None)
            for _v in forceseed:
                if _v not in seed:
                    seed[_v] = to_seed((m.get("concrete_values") or {}).get(_v, 0))
            unseeded_cubes += 1 if unseed else 0
        # canonical -> the base dump's ordinal; a canonical the base never
        # minted has no runtime key there: skip it rather than seed a guessed
        # ordinal.
        _canon_re = re.compile(
            r"(" + "|".join(sorted(map(re.escape, base_inv), key=len, reverse=True))
            + r")(?![0-9])") if base_inv else None
        for k, val in demanded.items():
            if "SYM_RESULT_" in k and re.search(r"_(?:records|to_ary)_[a-z_]+_[0-9a-f]{8}", k):
                if _canon_re is None or not _canon_re.search(k):
                    skipped_no_ordinal += 1
                    continue
                # Seed EVERY ordinal backing this canonical, not one arbitrary
                # pick: the alias map is many-to-one, so the path may evaluate
                # any of them and a single pick contradicts the demand whenever
                # it picks wrong (measured: 25% of evaluated seeds contradicted).
                m = _canon_re.search(k)
                for _ordn in base_inv[m.group(1)]:
                    seed[k[:m.start()] + _ordn + k[m.end():]] = val
            else:
                seed[k] = val
        # The model overlay may have re-introduced an UNSEEDED variable (the Z3
        # model assigns it a value like any other). Take it back out, and move
        # the OTHER operand of every companion `(V == X)` compare to the value
        # V actually takes when it is not seeded, read off this base's own dump.
        for _v in unseed:
            seed.pop(_v, None)
            _v0 = base_var_value(_base_path, _v)
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
print(f"combinations SKIPPED as environmentally unreachable "
      f"(campaign §7.4/§7.7): {skipped_unreachable}")
print(f"demanded lengths skipped because the base dump never minted that statement: {skipped_no_ordinal}")
print(f"cubes needing an UNSEEDED self-compare operand: {unseeded_cubes}"
      f"  (of which no clean base was available: {unseed_no_clean_base})")
