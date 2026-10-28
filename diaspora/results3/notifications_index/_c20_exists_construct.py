#!/usr/bin/env python3
"""C20 — construct the TEN `exists__5` / `exists__8` gap-sets by ORDINAL-MATCHED
overlay (see `_c20_exists_bases.py` for why the ordinal is the whole problem).

Per gap-set: take the K best bases the scan kept (they RECORD the demanded
`exists__<N>` ordinal and MINT every canonical the cube names), then overlay
every literal of the cube at the runtime seed key derived through that base's
own alias map.  `..._exists__<N>_exists` is itself a seedable Bool, so the
demanded outcome is written directly; the ordinal is what the base supplies.

usage: python3 _c20_exists_construct.py <cov.json> [K]
"""
import json, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402

VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
_ID = r"[A-Za-z_][A-Za-z0-9_]*"
_SELF = re.compile(rf"^\(({_ID}) == \1__prior\)$")
_EQT = re.compile(rf"^\(({_ID}) == (True|False)\)$")
_GTI = re.compile(rf"^\(({_ID}) > (-?\d+)\)$")
_EQS = re.compile(rf"^\(({_ID}) != StringVal\('((?:[^'\\]|\\.)*)'\)\)$")


def split_lits(nc):
    out = []
    for part in nc.split(" AND "):
        p, w = part.strip(), True
        if p.startswith("Not(") and p.endswith(")"):
            w, p = False, p[4:-1]
        out.append((p, w))
    return out


def main():
    cov = sys.argv[1]
    K = int(sys.argv[2]) if len(sys.argv) > 2 else 12
    miss = json.load(open(cov))["missing"]
    bs = json.load(open(os.path.join(HERE, "_c20_exists_bases.json")))
    meta = bs["meta"]
    per_variant, manifest = collections.defaultdict(list), []
    stats = collections.Counter()
    for gi, mm in enumerate(meta):
        lits = split_lits(miss[mm["missing_index"]]["node_constraint"])
        rows = bs["bases"].get(str(gi), [])[:K]
        stats[f"g{gi}_bases"] = len(rows)
        for r in rows:
            p = r["path"]
            if not os.path.exists(p):
                stats["base missing"] += 1
                continue
            d = json.load(open(p))
            amap = alias_map_for([(e.get("result_name"), e.get("note"))
                                  for e in d.get("events") or ()
                                  if e.get("type") == "symbolic_call"], ALIASES)
            rn = renamer(amap)
            rev = collections.defaultdict(list)
            for o, c in (amap or {}).items():
                rev[c].append(o)
            rev_sorted = sorted(rev, key=len, reverse=True)
            seeds = dict(d.get("concolic_seeds") or {})
            variant = next((v for v in VARIANTS
                            if os.path.basename(p).startswith("dump_" + v)), None)
            del d
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
            for e, want in lits:
                if _SELF.match(e):
                    for sk in seedkeys(_SELF.match(e).group(1)) or []:
                        seeds.pop(sk, None)
                    continue
                m = _EQT.match(e)
                if m:
                    v = m.group(1)
                    val = (m.group(2) == "True") if want else (m.group(2) != "True")
                    ks = seedkeys(v)
                    if not ks:
                        unres += 1
                    for sk in ks:
                        seeds[sk] = val
                        wrote += 1
                    continue
                m = _GTI.match(e)
                if m:
                    v, rhs = m.group(1), int(m.group(2))
                    ks = seedkeys(v)
                    if not ks:
                        unres += 1
                    for sk in ks:
                        seeds[sk] = rhs + 1 if want else max(0, rhs)
                        wrote += 1
                    continue
                unres += 1
            per_variant[variant].append(seeds)
            manifest.append({"gap": f"g{gi}", "missing_index": mm["missing_index"],
                             "base": os.path.basename(p), "variant": variant,
                             "base_match": r["match"], "base_conflict": r["conflict"],
                             "wrote": wrote, "unresolved": unres})
            stats["built"] += 1
            stats[f"unresolved:{unres}"] += 1
    for v in VARIANTS:
        json.dump(per_variant.get(v, []),
                  open(os.path.join(HERE, f"_c20_exists_seeds_{v}.json"), "w"))
    json.dump(manifest, open(os.path.join(HERE, "_c20_exists_manifest.json"), "w"), indent=1)
    print("stats:", dict(stats))
    print("per variant:", {v: len(per_variant.get(v, [])) for v in VARIANTS})
    print(f"C20-EXISTSCONSTRUCT-DONE {sum(len(x) for x in per_variant.values())} seeds")


if __name__ == "__main__":
    main()
