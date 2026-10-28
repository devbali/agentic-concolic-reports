#!/usr/bin/env python3
"""C20 — build the ACTIVE-FALSIFICATION probe set for the `exists?` alias.

The claim under test (C20 ALIAS):

    two `ActiveRecord::FinderMethods#exists?` call ORDINALS whose rendered
    statement (binds rewritten to the producing chain, literals wildcarded)
    is IDENTICAL are ONE decision.

The gate's own AliasAssumption test cannot reach it: `_test_alias` intervenes
by writing `len(<ordinal>_rows)` and an `exists?` result is a Bool with no
length, so `_alias_len` is None for every member and the verdict is a
structural NOT-TESTABLE. So the identity is falsified ACTIVELY, in the same
shape as `_test_alias` (ii): from one base, INTERVENE on each aliased ordinal
in turn and require the added/removed statement multisets to be IDENTICAL
across the ordinals of one canonical name.

Falsifier: any base on which flipping ordinal a and flipping ordinal b (same
canonical name, same base) produce DIFFERENT statement deltas, or move the
ordinals to different canonical names.

Writes `_c20_probe_seeds_<variant>.json` (the drive's EXTRA_SEEDS_JSON shape:
a list of seed dicts) and `_c20_probe_manifest.json` (seed dict digest ->
what it is), so the resulting dumps are matched back BY THEIR OWN SEEDS, never
by dump order.
"""
import hashlib, json, os, random, re, sys, collections
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import AliasAssumption, _alias_core   # noqa: E402
from _c20_scan2 import parse                                           # noqa: E402

EXISTS_PAT = r"SYM_RESULT_ActiveRecord__FinderMethods_exists__\d+"
_ORD_RE = re.compile(r"^SYM_RESULT_ActiveRecord__FinderMethods_exists__(\d+)$")
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
_ALIASES = None


def _aliases():
    import coverage_assumptions as ca
    return list(ca.ALIASES) + [AliasAssumption(result_pattern=EXISTS_PAT, key="statement")]


def digest(seeds):
    return hashlib.blake2b(json.dumps(seeds, sort_keys=True, default=str).encode(),
                           digest_size=10).hexdigest()


def survey(path):
    global _ALIASES
    if _ALIASES is None:
        _ALIASES = _aliases()
    try:
        evs, pcs, seeds, _v = parse(path)
    except Exception:
        return None
    amap, _k = _alias_core(evs, _ALIASES)
    groups = collections.defaultdict(list)
    for rn, c in amap.items():
        m = _ORD_RE.match(rn)
        if m:
            groups[c].append(m.group(1))
    groups = {c: sorted(o, key=int) for c, o in groups.items() if len(o) > 1}
    if not groups:
        return None
    return {"path": path, "groups": groups, "nseeds": len(seeds)}


def main():
    lst = sys.argv[1]
    sample = int(sys.argv[2]) if len(sys.argv) > 2 else 30000
    per_group = int(os.environ.get("BASES_PER_CANON", "8"))
    files = open(lst).read().split()
    random.seed(20260913)
    random.shuffle(files)
    files = files[:sample]
    found = collections.defaultdict(list)     # canonical -> [survey]
    with Pool(int(os.environ.get("JOBS", "3"))) as pool:
        for r in pool.imap_unordered(survey, files, chunksize=64):
            if not r:
                continue
            for c in r["groups"]:
                found[c].append(r)
    print(f"bases with a >=2-ordinal group, per canonical name:")
    for c, v in found.items():
        print(f"  {len(v):6d}  {c}")

    # pick bases: diverse in VARIANT and in the ORDINAL SET
    probes = collections.defaultdict(list)     # variant -> [seed dict]
    manifest = {}
    nbase = 0
    for c, rows in sorted(found.items()):
        seen = set()
        picked = []
        random.shuffle(rows)
        for r in rows:
            v = os.path.basename(r["path"]).split("_dse")[0][5:]
            k = (v, tuple(r["groups"][c]))
            if k in seen:
                continue
            seen.add(k)
            picked.append((r, v))
            if len(picked) >= per_group:
                break
        # if the diversity key exhausts, top up with the seed-richest rows
        for r in sorted(rows, key=lambda x: -x["nseeds"]):
            if len(picked) >= per_group:
                break
            v = os.path.basename(r["path"]).split("_dse")[0][5:]
            if any(r["path"] == p["path"] for p, _ in picked):
                continue
            picked.append((r, v))
        for r, v in picked:
            if v not in VARIANTS:
                continue
            base_seeds = json.load(open(r["path"]))["concolic_seeds"]
            ords = r["groups"][c]
            nbase += 1
            # the ALL-FALSE reference and one single-TRUE probe per ordinal
            ref = dict(base_seeds)
            for o in ords:
                ref[f"SYM_RESULT_ActiveRecord__FinderMethods_exists__{o}_exists"] = False
            variants = [("ref", None, dict(ref))]
            for o in ords:
                s = dict(ref)
                s[f"SYM_RESULT_ActiveRecord__FinderMethods_exists__{o}_exists"] = True
                variants.append(("flip", o, s))
            for kind, o, s in variants:
                d = digest(s)
                if d in manifest:
                    continue
                manifest[d] = {"canonical": c, "base": os.path.basename(r["path"]),
                               "variant": v, "ordinals": ords, "kind": kind,
                               "flipped": o, "seeds": s}
                probes[v].append(s)
    for v in VARIANTS:
        with open(os.path.join(HERE, f"_c20_probe_seeds_{v}.json"), "w") as fh:
            json.dump(probes.get(v, []), fh)
    with open(os.path.join(HERE, "_c20_probe_manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    tot = sum(len(x) for x in probes.values())
    print(f"BASES {nbase}  PROBE RUNS {tot}  variants "
          + " ".join(f"{v}:{len(probes.get(v, []))}" for v in VARIANTS))
    print("C20-PROBES-BUILT")


if __name__ == "__main__":
    main()
