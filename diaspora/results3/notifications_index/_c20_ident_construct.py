#!/usr/bin/env python3
"""C20 — construct the IDENTITY-COMPARE cube (the 11th gap-set of C19R1).

The cube (missing[0] of `_cov_C19_C19R1.json`, width 13) couples

    (find_by_1_person_id == devise_user_first_1_person_id)          TRUE
    (find_by_1_person_id == find_by_1_person_id__prior)             FALSE

C18R and §32.7 read the first as a var-var PIN and the second as an UNSEED,
found the clash, and made the PIN win — which necessarily contradicts the
self-compare (one value per key cannot differ from itself across calls).

`_c20_scan2.json` measures the OTHER direction on the corpus: **860 runs of
the 131 186 already record eq :: taken AND the self-compare :: not_taken, and
every one of them has `find_by_1_person_id` UNSEEDED.** So the pair is
co-realisable; what satisfies it is the UNSEED, with the equality carried by
the value the unseeded first call takes. This constructor therefore

  * takes its bases from exactly those runs,
  * leaves `..._find_by_1_person_id` UNSEEDED (never pins it),
  * seeds the OTHER 11 literals by the ordinary value rules, at the runtime
    (ordinal) seed key derived through the base's own alias map,
  * and writes a SECOND seed set (`B`) that ALSO pins the devise id to the
    value the base recorded for the find_by id, for the runs where the base's
    equality came out of a differing pair.

usage: python3 _c20_ident_construct.py <cov.json> <missing_index> [N_BASES]
"""
import json, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer          # noqa: E402
from coverage_assumptions import ALIASES                                 # noqa: E402

VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
FB = "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id"
DV = "SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id"
_ID = r"[A-Za-z_][A-Za-z0-9_]*"
_SELF = re.compile(rf"^\(({_ID}) == \1__prior\)$")
_EQT = re.compile(rf"^\(({_ID}) == (True|False)\)$")
_GTI = re.compile(rf"^\(({_ID}) > (-?\d+)\)$")
_CMP2 = re.compile(rf"^\(({_ID}) (==|!=) ({_ID})\)$")
# `True`/`False` also match _ID, so a `(X == True)` literal would be read
# as a var-var compare (C20 defect, found before any run was driven).
_BOOLRHS = ("True", "False")


def split_lits(nc):
    out = []
    for part in nc.split(" AND "):
        p = part.strip()
        want = True
        if p.startswith("Not(") and p.endswith(")"):
            want = False
            p = p[4:-1]
        out.append((p, want))
    return out


def main():
    cov, mi = sys.argv[1], int(sys.argv[2])
    nb = int(sys.argv[3]) if len(sys.argv) > 3 else 60
    d = json.load(open(cov))
    m = d["missing"][mi]
    lits = split_lits(m["node_constraint"])
    print(f"cube width {len(lits)}")
    # bases from `_c20_ident_bases.py`: they realise the coupled pair AND mint
    # every alias canonical the cube's names live under (without the second
    # condition the seed keys this script writes are inert -- the canonical
    # round-trips to itself and the runtime never reads it).
    bases = [os.path.basename(r["path"])
             for r in json.load(open(os.path.join(HERE, "_c20_ident_bases.json")))][:nb]
    print(f"bases (corpus runs already realising the coupled pair): {len(bases)}")

    per_variant = collections.defaultdict(list)
    manifest, stats = [], collections.Counter()
    for bn in bases:
        p = os.path.join(HERE, bn)
        if not os.path.exists(p):
            stats["base missing"] += 1
            continue
        dd = json.load(open(p))
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in dd.get("events") or ()
                              if e.get("type") == "symbolic_call"], ALIASES)
        rn = renamer(amap)
        rev = collections.defaultdict(list)
        for o, c in (amap or {}).items():
            rev[c].append(o)
        rev_sorted = sorted(rev, key=len, reverse=True)
        seeds = dict(dd.get("concolic_seeds") or {})
        variant = next((v for v in VARIANTS if bn.startswith("dump_" + v)), None)
        del dd
        if variant is None:
            stats["no variant"] += 1
            continue

        def seedkeys(k):
            dn = f"len({k[8:]})" if k.startswith("SYM_LEN_") else k
            outs = [dn]
            for c in rev_sorted:
                if re.search(re.escape(c) + r"(?![0-9])", dn):
                    outs = [re.sub(re.escape(c) + r"(?![0-9])",
                                   o.replace("\\", "\\\\"), dn) for o in rev[c]]
                    break
            return [o for o in outs if fixlen(rn(o)) == k]

        wrote = unres = 0
        clash_protected = []
        for e, want in lits:
            if _SELF.match(e):
                v = _SELF.match(e).group(1)
                for sk in seedkeys(v) or [v]:
                    if sk in seeds:
                        del seeds[sk]
                clash_protected.append(v)
                continue
            mm = _CMP2.match(e)
            if mm and mm.group(3) not in _BOOLRHS:
                a, op, b = mm.group(1), mm.group(2), mm.group(3)
                # THE CLASH. `a` is the UNSEEDED side (it is the self-compare's
                # own variable); pin only `b`, to the value `a` takes unseeded.
                if a in clash_protected or a == FB:
                    # THE CLASH, and the C20 correction: `a` is the UNSEEDED
                    # side, so the equality is carried by the value the base
                    # already realises -- and the base was CHOSEN because it
                    # records this literal with the demanded outcome. Writing
                    # `b` can only break it (the first C20 build pinned it to
                    # 0 while every base carries 1, and 80/80 runs then came
                    # back 12/13 with exactly this literal flipped).
                    continue
                for sk in (seedkeys(a) or []):
                    seeds[sk] = 0
                    wrote += 1
                for sk in (seedkeys(b) or []):
                    seeds[sk] = 0 if want and op == "==" else 1
                    wrote += 1
                continue
            mm = _EQT.match(e)
            if mm:
                v, rhs = mm.group(1), mm.group(2) == "True"
                val = rhs if want else (not rhs)
                ks = seedkeys(v)
                if not ks:
                    unres += 1
                for sk in ks:
                    seeds[sk] = val
                    wrote += 1
                continue
            mm = _GTI.match(e)
            if mm:
                v, rhs = mm.group(1), int(mm.group(2))
                val = rhs + 1 if want else max(0, rhs)
                ks = seedkeys(v)
                if not ks:
                    unres += 1
                for sk in ks:
                    seeds[sk] = val
                    wrote += 1
                continue
            unres += 1
        # the UNSEED must survive every later write
        for v in clash_protected + [FB]:
            for sk in seedkeys(v) or [v]:
                seeds.pop(sk, None)
        seeds.pop(FB, None)
        stats["built"] += 1
        stats[f"unresolved:{unres}"] += 1
        per_variant[variant].append(seeds)
        manifest.append({"base": bn, "variant": variant, "wrote": wrote,
                         "unresolved": unres, "fb_unseeded": FB not in seeds,
                         "dv": seeds.get(DV)})
    for v in VARIANTS:
        with open(os.path.join(HERE, f"_c20_ident_seeds_{v}.json"), "w") as fh:
            json.dump(per_variant.get(v, []), fh)
    with open(os.path.join(HERE, "_c20_ident_manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    print("stats:", dict(stats))
    print("per variant:", {v: len(per_variant.get(v, [])) for v in VARIANTS})
    print(f"C20-IDENT-CONSTRUCT-DONE {sum(len(x) for x in per_variant.values())} seeds")


if __name__ == "__main__":
    main()
