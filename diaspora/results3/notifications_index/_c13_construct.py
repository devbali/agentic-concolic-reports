#!/usr/bin/env python3
"""C13 — CONSTRUCT one seed per C12 witness leaf (RUNBOOK Phase 2:
construct-not-sample; the run is built from the checker's counterexample PLUS
the enabling gates, and the gates are read off the checker's own leaf, never
re-solved).

WHAT IT REPLACES. `_construct_all.py` (this batch, 2026-09-11) consumed the
EXACT ENUMERATOR's assignments. This one consumes the CHECKER's witnesses, which
is a different input with a different hazard, and it carries the repairs
posts_show measured on `_construct_by_gate.py` (§77.4) plus the two rules that
were already right here:

  (1) BOTH `len` SPELLINGS — already correct in `_construct_all.ordinals()`
      (`SYM_LEN_X` -> `len(X)` before ordinal resolution) and kept. Here the
      reverse map is DERIVED rather than written by hand: every seed key of the
      base is pushed through the loader's own transforms and must round-trip to
      the checker name, so a drift in either direction is counted, not silent.
  (2) SUFFIXED NAMES — `_construct_all._ordinals_raw` already did a PREFIX
      match (`canon.startswith(c)`), so posts_show's exact-lookup defect was
      never present here. What WAS silent is its `if not out: out = [canon]`
      fallback: it writes the CANONICAL name, which the runtime does not
      consume — an inert key. Those are now counted per seed.
  (3) MODEL COMPLETION IS NOT A DEMAND (§16d). One Z3 query per demand set means
      the witness model assigns EVERY variable, free ones included, from
      `model_completion`. Only variables the CUBE constrains are written; a free
      variable keeps the base run's own value.
  (4) OUT-OF-DOMAIN RESOLUTION FOR EVERY LITERAL KIND, VERIFIED. A value is
      accepted only if it satisfies EVERY literal the cube puts on that
      variable. Preference order: the model's value when it is one the corpus
      has actually produced; else the most-observed corpus value that satisfies
      the cube; else a synthesized sentinel (counted as kept-out-of-domain).
      This subsumes `_construct_all`'s `_GTI` snap-domain hack — an observed
      length is by construction already inside the mock's snapped domain — and
      extends the resolution `_construct_all` only did for integer `==`.
  (5) WRITE ORDER is not a hazard here. `_construct_all` needed negatives-first
      (§17.8/CT2) because it wrote one value per LITERAL; this constructor
      solves ONE value per VARIABLE against all of that variable's literals at
      once, so the eight `SYM_NOTE_TYPE_PROFILE == k` members can no longer
      clobber each other. Negatives are still emitted before positives so the
      output order matches the earlier batches' ledgers.
  (6) UNSEED, kept verbatim (§12.5, measured 402/402): `(V == V__prior)` is
      realised by the PRESENCE of V's seed key — taken by writing it, not-taken
      by DELETING it.
  (7) A ZERO LENGTH FORECLOSES ITS OWN ROWS (§12.10). When the cube constrains a
      row decision under a list, a satisfying non-zero length is preferred over
      a satisfying zero.

writes _c13_seeds_<variant>.json / _c13_seedsB_<variant>.json / _c13_manifest.json
"""
import json, os, pickle, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
GAPS  = os.environ.get("C13_GAPS",  os.path.join(HERE, "_c13_gaps.json"))
INDEX = os.environ.get("C13_INDEX", os.path.join(HERE, "_c13_index.pkl"))
K     = int(os.environ.get("BASES_PER_GAP", "2"))
# ROUND-scoped output names: each round writes its own seed files and manifest
PREF_A = os.environ.get("C13_PREF_A", "_c13_seeds_")
PREF_B = os.environ.get("C13_PREF_B", "_c13_seedsB_")
MANIFEST = os.environ.get("C13_MANIFEST", "_c13_manifest.json")
PIN   = 424242
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")

_ID = r"[A-Za-z_][A-Za-z0-9_]*"
_SELF = re.compile(rf"^\(({_ID}) == \1__prior\)$")
_SELFN = re.compile(rf"^\(({_ID}) != \1\)$")
_CMP2 = re.compile(rf"^\(({_ID}) (==|!=) ({_ID})\)$")
_EQT  = re.compile(rf"^\(({_ID}) == (True|False)\)$")
_EQI  = re.compile(rf"^\(({_ID}) == (-?\d+)\)$")
_NEI  = re.compile(rf"^\(({_ID}) != (-?\d+)\)$")
_GTI  = re.compile(rf"^\(({_ID}) > (-?\d+)\)$")
_GEI  = re.compile(rf"^\(({_ID}) >= (-?\d+)\)$")
_LTI  = re.compile(rf"^\(({_ID}) < (-?\d+)\)$")
_LEI  = re.compile(rf"^\(({_ID}) <= (-?\d+)\)$")
_EQS  = re.compile(rf"^\(({_ID}) == (?:StringVal\()?'((?:[^'\\]|\\.)*)'\)?\)$")
_NES  = re.compile(rf"^\(({_ID}) != (?:StringVal\()?'((?:[^'\\]|\\.)*)'\)?\)$")
_LEN  = re.compile(r"len\(([^()]+)\)")


def parse_cube(cube):
    """-> (cons {var: [(kind, rhs, want)]}, unseed {var: want}, pairs [(a,op,b,want)],
            unparsed [expr])."""
    cons, unseed, pairs, bad = defaultdict(list), {}, [], []
    for e, want in cube:
        m = _SELF.match(e)
        if m:
            unseed[m.group(1)] = want
            continue
        if _SELFN.match(e):
            continue                       # a self-compare constrains nothing
        m = _EQT.match(e)
        if m:
            cons[m.group(1)].append(("eq", m.group(2) == "True", want)); continue
        for rx, kind, cast in ((_EQI, "eq", int), (_NEI, "ne", int),
                               (_GTI, "gt", int), (_GEI, "ge", int),
                               (_LTI, "lt", int), (_LEI, "le", int),
                               (_EQS, "eq", str), (_NES, "ne", str)):
            m = rx.match(e)
            if m:
                cons[m.group(1)].append((kind, cast(m.group(2)), want)); break
        else:
            m = _CMP2.match(e)
            if m:
                pairs.append((m.group(1), m.group(2), m.group(3), want)); continue
            bad.append(e)
    return dict(cons), unseed, pairs, bad


def sat(val, lits):
    for kind, rhs, want in lits:
        try:
            if kind == "eq":
                ok = (val == rhs)
            elif kind == "ne":
                ok = (val != rhs)
            elif kind == "gt":
                ok = (val > rhs)
            elif kind == "ge":
                ok = (val >= rhs)
            elif kind == "lt":
                ok = (val < rhs)
            else:
                ok = (val <= rhs)
        except TypeError:
            return False
        if ok != want:
            return False
    return True


def synth(lits):
    """A value satisfying every literal, invented. Last resort."""
    for kind, rhs, want in lits:
        if kind == "eq" and want:
            return rhs
    cands = []
    for kind, rhs, want in lits:
        if isinstance(rhs, bool):
            cands += [True, False]
        elif isinstance(rhs, int):
            cands += [rhs, rhs + 1, rhs - 1, rhs + PIN, 0, 1, 4]
        elif isinstance(rhs, str):
            cands += [rhs, rhs + "_c13other", ""]
    for c in cands:
        if sat(c, lits):
            return c
    return None


def main():
    t0 = time.time()
    idx = pickle.load(open(INDEX, "rb"))
    exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
    domain = idx["domain"]
    raw = {tuple(k.split("\x00", 1)): v for k, v in idx["raw"].items()}
    canon = idx["canon"]; cbit = {c: i for i, c in enumerate(canon)}
    gaps = json.load(open(GAPS))
    dumps = idx["dumps"]
    print(f"gaps {len(gaps)}   dumps {len(dumps)}   canon {len(canon)}   K={K}", flush=True)

    # ---- collapse dumps to distinct PROFILES. Base choice only ever reads
    # (variant, eval mask, true mask, canonical mask); 114 610 dumps carry far
    # fewer distinct profiles, and scoring every gap against every dump would
    # be 8.9e7 comparisons for nothing. The representative is the dump with the
    # most seeds (the richest context).
    prof = {}
    for p, v, em, tm, ns, cm in dumps:
        key = (v, em, tm, cm)
        cur = prof.get(key)
        if cur is None or ns > cur[1]:
            prof[key] = (p, ns)
    profiles = [(p, v, em, tm, ns, cm) for (v, em, tm, cm), (p, ns) in prof.items()]
    print(f"distinct base profiles: {len(profiles)}  ({time.time()-t0:.0f}s)", flush=True)

    UNIV = (1 << len(exprs)) - 1
    _need = {}

    def canon_need(name):
        m = _need.get(name)
        if m is None:
            dn = f"len({name[8:]})" if name.startswith("SYM_LEN_") else name
            m = 0
            for c, j in cbit.items():
                if re.search(re.escape(c) + r"(?![0-9])", dn):
                    m |= 1 << j
            _need[name] = m
        return m

    # ---------------------------------------------------------- base choice
    chosen = {}
    for n, g in enumerate(gaps):
        if n and n % 200 == 0:
            print(f"  base choice {n}/{len(gaps)}  {time.time()-t0:.0f}s", flush=True)
        cons, unseed, pairs, bad = parse_cube(g["cube"])
        names = set(cons) | set(unseed)
        for a, _o, b, _w in pairs:
            names.add(a); names.add(b)
        need = 0
        for v in names:
            need |= canon_need(v)
        nneed = need.bit_count()
        gt = gf = 0
        for e, o in g["cube"]:
            j = eidx.get(e)
            if j is None:
                continue
            if o:
                gt |= 1 << j
            else:
                gf |= 1 << j
        scored = []
        for di, (p, v, em, tm, ns, cm) in enumerate(profiles):
            fm = em & ~tm & UNIV
            match = ((gt & tm).bit_count() + (gf & fm).bit_count())
            conflict = ((gt & fm).bit_count() + (gf & tm).bit_count())
            scored.append(((need & cm).bit_count(), match - conflict, ns, di))
        scored.sort(reverse=True)
        picks, seen_v = [], set()
        for s in scored:
            if len(picks) >= K:
                break
            v = profiles[s[3]][1]
            if v in seen_v and len(seen_v) < K:
                continue
            picks.append(s); seen_v.add(v)
        for s in scored:
            if len(picks) >= K:
                break
            if s not in picks:
                picks.append(s)
        chosen[g["id"]] = (picks, nneed, cons, unseed, pairs, bad)
    print(f"base choice done {time.time()-t0:.0f}s", flush=True)

    # ------------------------------------------------------- build the seeds
    sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
    from concolic_engine.assumptions import alias_map_for, renamer
    from coverage_assumptions import ALIASES
    fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s

    work = defaultdict(list)
    for g in gaps:
        picks = chosen[g["id"]][0]
        for r, s in enumerate(picks):
            work[s[3]].append((g, r, s))
    print(f"distinct base runs used: {len(work)}", flush=True)

    per_variant, manifest, stat = defaultdict(list), [], Counter()
    unresolved_names, subbed, kept_ood, unsat_names = Counter(), Counter(), Counter(), Counter()
    pairclash_names = Counter()
    for bi, jobs in work.items():
        path, variant, em, tm, ns, cm = profiles[bi]
        d = json.load(open(path))
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in d.get("events") or ()
                              if e.get("type") == "symbolic_call"], ALIASES)
        rn = renamer(amap)
        base_seeds = dict(d.get("concolic_seeds") or {})
        rev = defaultdict(list)
        for o, c in (amap or {}).items():
            rev[c].append(o)
        rev_sorted = sorted(rev, key=len, reverse=True)
        del d
        _ck = {}

        def seedkeys(k):
            """Checker name -> every RUNTIME seed key backing it, DERIVED: the
            candidate is pushed back through the loader's own transforms and
            must round-trip to `k`. Returns [] when the base cannot spell it."""
            if k in _ck:
                return _ck[k]
            dn = f"len({k[8:]})" if k.startswith("SYM_LEN_") else k
            outs = [dn]
            for c in rev_sorted:
                if re.search(re.escape(c) + r"(?![0-9])", dn):
                    outs = [re.sub(re.escape(c) + r"(?![0-9])",
                                   o.replace("\\", "\\\\"), dn) for o in rev[c]]
                    break
            good = [o for o in outs if fixlen(rn(o)) == k]
            _ck[k] = good
            return good

        for g, rank, score in jobs:
            picks, nneed, cons, unseed, pairs, bad = chosen[g["id"]]
            model = g["model"]
            seeds = dict(base_seeds)
            nwrit = nsub = nkept = nunres = nunsat = nnovel = 0
            npairclash = 0
            # (7) a length whose list also carries a constrained row decision
            rowed = set()
            for v in cons:
                if not v.startswith("SYM_LEN_"):
                    continue
                inner = v[8:]
                stem = inner[:-5] if inner.endswith("_rows") else inner
                if any(o != v and o.startswith(stem) for o in cons):
                    rowed.add(v)

            def resolve(v, lits):
                nonlocal nsub, nkept, nunsat
                dom = domain.get(v) or {}
                mv = model.get(v, None)
                if mv is not None and repr(mv) in dom and sat(mv, lits):
                    return mv, True
                # §19.7: the OUT-OF-DOMAIN values in this corpus are the
                # previous constructor's own negation sentinels (k + PIN) —
                # measured ZERO occurrences in non-constructed dumps. They are
                # in `domain` because they were replayed; they are not values
                # the APP produces, so they are never a legitimate substitute.
                cand = [(c, raw[(v, r)]) for r, c in dom.items()
                        if not (isinstance(raw[(v, r)], int)
                                and not isinstance(raw[(v, r)], bool)
                                and abs(raw[(v, r)]) >= PIN)
                        and sat(raw[(v, r)], lits)]
                if cand:
                    if v in rowed:
                        nz = [x for x in cand if x[1] != 0]
                        if nz:
                            cand = nz
                    cand.sort(key=lambda x: -x[0])
                    nsub += 1; subbed[v] += 1
                    return cand[0][1], True
                s = synth(lits)
                if s is None:
                    nunsat += 1; unsat_names[v] += 1
                    return None, False
                nkept += 1; kept_ood[v] += 1
                return s, True

            values = {}
            # §32 (2026-09-13): the variables a VAR-VAR compare PINS.
            # An UNSEED on the same variable used to run LAST and
            # `seeds.pop` the pin, so the equality was silently dropped
            # and only ONE side of it reached the seed file (measured on
            # notifications cube c000824: the identity literal pinned
            # `find_by_1_person_id`, its own `== ..._prior` UNSEED then
            # deleted it, and the C16 seed carried the devise side alone
            # — campaign §31.4). The two demands are not JOINTLY
            # seedable: one value per key cannot also differ from itself
            # across calls. The PIN now wins and the conflict is COUNTED,
            # never silent.
            pair_pinned = set()
            for v, lits in cons.items():
                val, ok = resolve(v, lits)
                if ok:
                    values[v] = val
            # two-variable compares: pin both, preferring observed values
            for a, op, b, want in pairs:
                eq = (want == (op == "=="))
                av = values.get(a)
                if av is None:
                    da = domain.get(a) or {}
                    av = raw[(a, max(da, key=da.get))] if da else PIN
                if eq:
                    bv = av
                else:
                    db = domain.get(b) or {}
                    bv = next((raw[(b, r)] for r, _c in
                               sorted(db.items(), key=lambda x: -x[1])
                               if raw[(b, r)] != av), None)
                    if bv is None:
                        bv = (av + 1) if isinstance(av, int) and not isinstance(av, bool) \
                             else str(av) + "_c13other"
                values[a] = av
                pair_pinned.add(a)
                if b not in cons:
                    values[b] = bv
                    pair_pinned.add(b)
                elif not sat(bv, cons[b]):
                    pass                     # the single-variable literals win
                else:
                    values[b] = bv
                    pair_pinned.add(b)
            # (5) negatives first, positives last (ledger order; not needed for
            # correctness any more — one value per variable already)
            order = sorted(values, key=lambda v: 0 if not any(
                k == "eq" and w for k, _r, w in cons.get(v, ())) else 1)
            for v in order:
                sks = seedkeys(v)
                if not sks:
                    nunres += 1; unresolved_names[v] += 1
                    continue
                for sk in sks:
                    if sk not in base_seeds:
                        nnovel += 1
                    seeds[sk] = values[v]
                nwrit += 1
            # (6) UNSEED — presence of the key IS the decision
            for v, want in unseed.items():
                if v in pair_pinned:
                    npairclash += 1; pairclash_names[v] += 1
                    continue        # the var-var pin wins; counted below
                sks = seedkeys(v)
                if not sks:
                    nunres += 1; unresolved_names[v] += 1
                    continue
                if want:
                    dm = domain.get(v) or {}
                    val = raw[(v, max(dm, key=dm.get))] if dm else PIN
                    for sk in sks:
                        seeds[sk] = val
                else:
                    for sk in sks:
                        seeds.pop(sk, None)
                nwrit += 1
            seeds["__c13gap__"] = g["id"]
            per_variant[(rank, variant)].append(seeds)
            manifest.append({
                "gap": g["id"], "set": g["set"], "width": g["width"],
                "set_capped": g["set_capped"], "variant": variant,
                "seed_set": "A" if rank == 0 else "B",
                "seed_file": (PREF_A if rank == 0 else PREF_B) + variant + ".json",
                "seed_index": len(per_variant[(rank, variant)]) - 1,
                "base": os.path.basename(path), "base_rank": rank,
                "why": {"alias_canonicals_covered": f"{score[0]}/{nneed}",
                        "cube_match_minus_conflict": f"{score[1]}/{g['width']}",
                        "base_seeds": score[2]},
                "values_written": nwrit, "substituted": nsub,
                "kept_out_of_domain": nkept, "not_seedable": nunres,
                "unsatisfiable": nunsat, "unparsed": bad,
                "keys_novel_to_base": nnovel,
            })
            stat["seeds"] += 1; stat["subst"] += nsub; stat["kept"] += nkept
            stat["unres"] += nunres; stat["unsat"] += nunsat
            stat["pairclash"] += npairclash
            stat["novel"] += nnovel
            if nunres:
                stat["seeds_with_unseedable_member"] += 1
            if score[1] < g["width"]:
                stat["seeds_on_imperfect_base"] += 1
            if score[0] < nneed:
                stat["seeds_with_an_inert_alias"] += 1
            if bad:
                stat["seeds_with_unparsed_expr"] += 1

    for rank, pref in ((0, PREF_A), (1, PREF_B)):
        for v in VARIANTS:
            lst = per_variant.get((rank, v), [])
            json.dump(lst, open(os.path.join(HERE, f"{pref}{v}.json"), "w"))
            print(f"  set {'A' if rank == 0 else 'B'} {v:13s}: {len(lst)} seeds")
    json.dump(manifest, open(os.path.join(HERE, MANIFEST), "w"))

    print(f"\nseeds built                 : {stat['seeds']}  ({len(gaps)} gaps x K={K})")
    print(f"values SUBSTITUTED          : {stat['subst']} (model value not one the "
          f"corpus produces; replaced by the most-observed value SATISFYING the cube)")
    print(f"values kept out-of-domain   : {stat['kept']} (no observed value satisfies)")
    print(f"var-var PIN beat an UNSEED : {stat['pairclash']} over "
          f"{len(pairclash_names)} name(s) — the equality is seeded, the "
          f"self-compare it clashes with is NOT (§32)")
    for k, c in pairclash_names.most_common(4):
        print(f"    {c:5d}  {k}")
    print(f"values NOT SEEDABLE         : {stat['unres']} over {len(unresolved_names)} "
          f"variables, in {stat['seeds_with_unseedable_member']} seeds")
    print(f"variables with NO satisfying value at all: {stat['unsat']} "
          f"({len(unsat_names)} names)")
    for k, c in unresolved_names.most_common(8):
        print(f"     not-seedable x{c:<5} {k[:90]}")
    for k, c in unsat_names.most_common(8):
        print(f"     unsatisfiable x{c:<5} {k[:90]}")
    print(f"seeds whose base does NOT already walk the whole cube: "
          f"{stat['seeds_on_imperfect_base']} (expected — the cube is what no run "
          f"walked; the SEED pins it, the base only supplies context)")
    print(f"keys written that the base was NOT already seeded on: {stat['novel']} "
          f"(stated, not hidden: a key the run does not mint is inert — this is the "
          f"upper bound on that, and base choice by alias coverage is what minimises it)")
    print(f"seeds with an INERT alias (base cannot spell a canonical): "
          f"{stat['seeds_with_an_inert_alias']}")
    print(f"seeds with an UNPARSED expr: {stat.get('seeds_with_unparsed_expr', 0)}")
    print("top substituted variables")
    for k, c in subbed.most_common(6):
        print(f"     x{c:<6} {k[:90]}")
    print("top kept-out-of-domain variables")
    for k, c in kept_ood.most_common(6):
        print(f"     x{c:<6} {k[:90]}")
    print(f"C13-CONSTRUCT-DONE {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
