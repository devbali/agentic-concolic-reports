#!/usr/bin/env python3
"""C14 — CONSTRUCT every remaining cube by PER-LEAF-GROUP OVERLAY.

Difference from `_c13_construct.py`, which this reuses wholesale for the value
rules (§25.3's four repairs, UNSEED, both `len` spellings, the derived reverse
seed-key map):

  * INPUT is the EXACT ENUMERATOR's full remaining list, not the checker's
    capped witnesses. A demand set contributes EVERY uncovered assignment, so
    a round is no longer ceilinged at one leaf per set.
  * BASE CHOICE IS PER LEAF GROUP, not per cube. A leaf group is
    (demand set x gate prefix), which is exactly the granularity at which
    "gate-matched" is well defined — two leaf groups of one set pin different
    gates, so ONE base per SET cannot be gate-matched for both. The base is
    scored by, in order: alias-canonical coverage of every name the group's
    cubes touch (§19's alias-walk lesson), gate-prefix match minus conflict,
    how many of the group's MEMBER decisions the base actually evaluates
    (a seed on a decision the base never walks is inert), and seed richness.
  * Every cube of the group is then OVERLAID on that one base.

writes <PREF><variant>.json and <MANIFEST>
"""
import json, os, pickle, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from _c13_construct import parse_cube, sat, synth, PIN, VARIANTS, _LEN  # noqa: E402

GAPS  = os.environ.get("C14_GAPS",  os.path.join(HERE, "_c14_gaps.json"))
INDEX = os.environ.get("C14_INDEX", os.path.join(HERE, "_c14_index.pkl"))
K     = int(os.environ.get("BASES_PER_GROUP", "1"))
PREF  = os.environ.get("C14_PREF", "_c14_seeds_")
PREFB = os.environ.get("C14_PREFB", "_c14_seedsB_")
MANIFEST = os.environ.get("C14_MANIFEST", "_c14_manifest.json")


def main():
    t0 = time.time()
    idx = pickle.load(open(INDEX, "rb"))
    exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
    domain = idx["domain"]
    raw = {tuple(k.split("\x00", 1)): v for k, v in idx["raw"].items()}
    canon = idx["canon"]; cbit = {c: i for i, c in enumerate(canon)}
    gaps = json.load(open(GAPS))
    dumps = idx["dumps"]
    bygroup = defaultdict(list)
    for g in gaps:
        bygroup[g["group"]].append(g)
    print(f"cubes {len(gaps)}  leaf groups {len(bygroup)}  dumps {len(dumps)}  "
          f"canon {len(canon)}  K={K}", flush=True)

    # -------- profiles. At 440 expressions almost every dump is its own
    # profile (115 233 of 116 570), so scoring every profile against every
    # group is 1.3e8 python iterations. Instead the choice is done with
    # INVERTED BITSETS over profiles — one big int per (expr, polarity) and
    # per alias canonical — and §19.4's installed rule: intersect greedily,
    # NEVER emptying the candidate set, in the order
    #     alias canonicals  ->  gate prefix  ->  the group's member decisions
    # then take the seed-richest survivor. Same rule, ~0.6 ms per group.
    prof = {}
    for p, v, em, tm, ns, cm in dumps:
        key = (v, em, tm, cm)
        cur = prof.get(key)
        if cur is None or ns > cur[1]:
            prof[key] = (p, ns)
    profiles = [(p, v, em, tm, ns, cm) for (v, em, tm, cm), (p, ns) in prof.items()]
    N = len(profiles)
    print(f"distinct base profiles: {N}  ({time.time()-t0:.0f}s)", flush=True)
    UNIV = (1 << len(exprs)) - 1

    NB = (N + 7) // 8
    TBS = [bytearray(NB) for _ in exprs]
    FBS = [bytearray(NB) for _ in exprs]
    EBS = [bytearray(NB) for _ in exprs]
    CBS = [bytearray(NB) for _ in canon]
    for i, (_p, _v, em, tm, _ns, cm) in enumerate(profiles):
        by, bit = i >> 3, 1 << (i & 7)
        m = em
        while m:
            b = m & -m; j = b.bit_length() - 1; m ^= b
            EBS[j][by] |= bit
            if (tm >> j) & 1:
                TBS[j][by] |= bit
            else:
                FBS[j][by] |= bit
        m = cm
        while m:
            b = m & -m; j = b.bit_length() - 1; m ^= b
            CBS[j][by] |= bit
    to_int = lambda ba: int.from_bytes(bytes(ba), "little")
    TBS = [to_int(x) for x in TBS]; FBS = [to_int(x) for x in FBS]
    EBS = [to_int(x) for x in EBS]; CBS = [to_int(x) for x in CBS]
    ALL = (1 << N) - 1
    # profiles by seed richness, richest first — the tie-break scan
    rich = sorted(range(N), key=lambda i: -profiles[i][4])
    print(f"inverted bitsets built  ({time.time()-t0:.0f}s)", flush=True)

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

    # ------------------------------------------------ base choice, per GROUP
    parsed = {}
    chosen = {}
    for n, (gid, cubes) in enumerate(sorted(bygroup.items())):
        if n and n % 200 == 0:
            print(f"  base choice {n}/{len(bygroup)}  {time.time()-t0:.0f}s", flush=True)
        need = 0
        members = set()
        for g in cubes:
            cons, unseed, pairs, bad = parse_cube([(e, o) for e, o in g["cube"]])
            parsed[g["id"]] = (cons, unseed, pairs, bad)
            names = set(cons) | set(unseed)
            for a, _o, b, _w in pairs:
                names.add(a); names.add(b)
            for v in names:
                need |= canon_need(v)
            for e, _o in g["cube"]:
                members.add(e)
        pre = cubes[0]["pre"]
        members -= set(pre)
        nneed = need.bit_count()
        cand = ALL
        got_c = 0
        m = need
        while m:
            b = m & -m; j = b.bit_length() - 1; m ^= b
            nxt = cand & CBS[j]
            if nxt:
                cand = nxt; got_c += 1
        npre = got_g = 0
        for e, o in pre.items():
            j = eidx.get(e)
            if j is None:
                continue
            npre += 1
            nxt = cand & (TBS[j] if o else FBS[j])
            if nxt:
                cand = nxt; got_g += 1
        nmem = got_m = 0
        for e in members:
            j = eidx.get(e)
            if j is None:
                continue
            nmem += 1
            nxt = cand & EBS[j]
            if nxt:
                cand = nxt; got_m += 1
        picks = []
        seen_v = set()
        for i in rich:
            if len(picks) >= K:
                break
            if not ((cand >> i) & 1):
                continue
            v = profiles[i][1]
            if v in seen_v and len(seen_v) < K:
                continue
            picks.append((got_c, got_g, got_m, profiles[i][4], i))
            seen_v.add(v)
        if not picks:                       # cannot happen (cand is never empty)
            picks = [(got_c, got_g, got_m, profiles[rich[0]][4], rich[0])]
        chosen[gid] = (picks, nneed, npre, nmem)
    print(f"base choice done {time.time()-t0:.0f}s", flush=True)

    # ------------------------------------------------------- build the seeds
    sys.path.insert(0, "/home/dev/project/src")
    from concolic_engine.assumptions import alias_map_for, renamer
    from coverage_assumptions import ALIASES
    fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s

    work = defaultdict(list)
    for gid, cubes in bygroup.items():
        for r, s in enumerate(chosen[gid][0]):
            for g in cubes:
                work[s[4]].append((g, r, s, gid))
    print(f"distinct base runs used: {len(work)}", flush=True)

    per_variant, manifest, stat = defaultdict(list), [], Counter()
    unresolved_names, subbed, kept_ood, unsat_names = (Counter(), Counter(),
                                                       Counter(), Counter())
    nb = 0
    for bi, jobs in work.items():
        nb += 1
        if nb % 200 == 0:
            print(f"  bases {nb}/{len(work)}  seeds {stat['seeds']}  "
                  f"{time.time()-t0:.0f}s", flush=True)
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

        for g, rank, score, gid in jobs:
            cons, unseed, pairs, bad = parsed[g["id"]]
            model = {}
            seeds = dict(base_seeds)
            nwrit = nsub = nkept = nunres = nunsat = nnovel = 0
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
            for v, lits in cons.items():
                val, ok = resolve(v, lits)
                if ok:
                    values[v] = val
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
                             else str(av) + "_c14other"
                values[a] = av
                if b not in cons:
                    values[b] = bv
                elif not sat(bv, cons[b]):
                    pass
                else:
                    values[b] = bv
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
            for v, want in unseed.items():
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
            # the marker key is the C13 one so `_c13_classify.py` reads these
            # dumps verbatim (one classifier, one definition of HONOURED)
            seeds["__c13gap__"] = g["id"]
            per_variant[(rank, variant)].append(seeds)
            _pref = PREF if rank == 0 else PREFB
            manifest.append({
                "gap": g["id"], "cube": g["id"], "set": g["set"], "group": gid,
                "width": g["width"], "set_capped": False, "variant": variant,
                "reachable": g["reachable"],
                "seed_set": "A" if rank == 0 else "B",
                "seed_file": _pref + variant + ".json",
                "seed_index": len(per_variant[(rank, variant)]) - 1,
                "base": os.path.basename(path), "base_rank": rank,
                "why": {"alias_canonicals_covered": f"{score[0]}/{chosen[gid][1]}",
                        "gate_literals_matched": f"{score[1]}/{chosen[gid][2]}",
                        "group_members_evaluated": f"{score[2]}/{chosen[gid][3]}",
                        "base_seeds": score[3]},
                "values_written": nwrit, "substituted": nsub,
                "kept_out_of_domain": nkept, "not_seedable": nunres,
                "unsatisfiable": nunsat, "unparsed": bad,
                "keys_novel_to_base": nnovel,
            })
            stat["seeds"] += 1; stat["subst"] += nsub; stat["kept"] += nkept
            stat["unres"] += nunres; stat["unsat"] += nunsat
            stat["novel"] += nnovel
            if nunres:
                stat["seeds_with_unseedable_member"] += 1
            if score[0] < chosen[gid][1]:
                stat["seeds_with_an_inert_alias"] += 1
            if score[1] < chosen[gid][2]:
                stat["seeds_on_gate_imperfect_base"] += 1
            if bad:
                stat["seeds_with_unparsed_expr"] += 1

    for rank, pref in ((0, PREF), (1, PREFB)):
        if rank and K < 2:
            break
        for v in VARIANTS:
            lst = per_variant.get((rank, v), [])
            json.dump(lst, open(os.path.join(HERE, f"{pref}{v}.json"), "w"))
            print(f"  set {'A' if rank == 0 else 'B'} {v:13s}: {len(lst)} seeds")
    json.dump(manifest, open(os.path.join(HERE, MANIFEST), "w"))

    print(f"\nseeds built                 : {stat['seeds']}  "
          f"({len(gaps)} cubes x K={K})")
    print(f"values SUBSTITUTED          : {stat['subst']}")
    print(f"values kept out-of-domain   : {stat['kept']} (no observed value satisfies)")
    print(f"values NOT SEEDABLE         : {stat['unres']} over "
          f"{len(unresolved_names)} variables, in "
          f"{stat['seeds_with_unseedable_member']} seeds")
    print(f"variables with NO satisfying value at all: {stat['unsat']} "
          f"({len(unsat_names)} names)")
    for k, c in unresolved_names.most_common(8):
        print(f"     not-seedable x{c:<6} {k[:90]}")
    for k, c in unsat_names.most_common(8):
        print(f"     unsatisfiable x{c:<6} {k[:90]}")
    print(f"seeds on a base that does NOT walk the whole GATE prefix: "
          f"{stat['seeds_on_gate_imperfect_base']}")
    print(f"seeds with an INERT alias   : {stat['seeds_with_an_inert_alias']}")
    print(f"keys novel to the base      : {stat['novel']}")
    print(f"seeds with an UNPARSED expr : {stat.get('seeds_with_unparsed_expr', 0)}")
    for lbl, ctr in (("top substituted", subbed), ("top kept-out-of-domain", kept_ood)):
        print(lbl)
        for k, c in ctr.most_common(6):
            print(f"     x{c:<6} {k[:90]}")
    print(f"C14-CONSTRUCT-DONE {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
