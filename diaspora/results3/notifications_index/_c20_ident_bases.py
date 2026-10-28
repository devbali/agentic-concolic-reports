#!/usr/bin/env python3
"""C20 — find BASES for the identity-compare cube.

A usable base must (a) already record `(FB == DV) :: taken` AND the
self-compare `(FB == FB) :: not_taken` — the coupled pair the seeder cannot
write — and (b) MINT every alias canonical the cube's names live under, or
the seed keys the constructor writes are inert (the defect this script exists
to prevent: a canonical the base never mints round-trips through `seedkeys`
to itself and is written as a seed the runtime never reads).

Ranks by how many of the cube's literals the base already matches.
usage: python3 _c20_ident_bases.py <cov.json> <missing_index> <dump_list> <out.json>
"""
import json, os, re, sys, collections
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402
from _c20_scan2 import parse                                      # noqa: E402

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
FB = "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id"
DV = "SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id"
EQ, SELF = f"({FB} == {DV})", f"({FB} == {FB})"
_CANON_RE = re.compile(r"SYM_RESULT_[A-Za-z0-9_]*?_(?:notifications|aspect_memberships|"
                       r"photos|tags|aspects|services|mentions)_[0-9a-f]{8}")
LITS = CANONS = None


def work(path):
    try:
        evs, pcs, seeds, _v = parse(path)
    except Exception:
        return None
    amap = alias_map_for(evs, ALIASES)
    mint = set(amap.values())
    if not CANONS <= mint:
        return None
    rn = renamer(amap)
    eq = selfc = None
    seen = {}
    for expr, taken, _s in pcs:
        if expr == EQ:
            eq = taken
        elif expr == SELF:
            selfc = taken if selfc is None else (selfc if selfc == taken else "BOTH")
        seen.setdefault(fixlen(rn(expr)), set()).add(bool(taken))
    if eq is not True or selfc is not False:
        return None
    match = sum(1 for e, w in LITS if e in seen and w in seen[e])
    confl = sum(1 for e, w in LITS if e in seen and (not w) in seen[e] and w not in seen[e])
    return {"path": path, "match": match, "conflict": confl, "nseeds": len(seeds),
            "variant": next((v for v in ("html_plain", "html_typed", "json_plain",
                                         "json_typed", "mobile_plain", "mobile_typed",
                                         "xml_plain")
                             if os.path.basename(path).startswith("dump_" + v)), "?")}


def _init(lits, canons):
    global LITS, CANONS
    LITS, CANONS = lits, canons


def main():
    cov, mi, lst, outp = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
    m = json.load(open(cov))["missing"][mi]
    lits = []
    for part in m["node_constraint"].split(" AND "):
        p, w = part.strip(), True
        if p.startswith("Not(") and p.endswith(")"):
            w, p = False, p[4:-1]
        lits.append((p, w))
    canons = set()
    for e, _w in lits:
        canons |= set(_CANON_RE.findall(e))
    print(f"cube width {len(lits)}; canonicals the base must mint: {sorted(canons)}")
    files = open(lst).read().split()
    out = []
    with Pool(int(os.environ.get("JOBS", "2")), initializer=_init,
              initargs=(lits, canons)) as pool:
        for i, r in enumerate(pool.imap_unordered(work, files, chunksize=64)):
            if r:
                out.append(r)
            if (i + 1) % 20000 == 0:
                print(f"  [{i+1}/{len(files)}] usable bases {len(out)}", flush=True)
    out.sort(key=lambda r: (-r["match"], r["conflict"], -r["nseeds"]))
    json.dump(out[:400], open(outp, "w"), indent=1)
    print(f"USABLE BASES {len(out)}  best match {out[0]['match'] if out else 0}/{len(lits)}  "
          f"variants {collections.Counter(r['variant'] for r in out[:400])}")
    print(f"C20-IDENTBASES-DONE {outp}")


if __name__ == "__main__":
    main()
