#!/usr/bin/env python3
"""C20 — bases for the TEN `exists__5`/`exists__8` gap-sets, selected BY THE
ORDINAL CONTEXT.

The 10 sets are not blocked by an inference gap: they are blocked because in
the leaf's context the `exists?` decision is minted under a DIFFERENT call
ordinal, and the demand names ordinal 5 (or 8).  The ordinal is a function of
the call prefix, and the prefix is seedable — how many `diaspora://` links
render before the header's `admin?` / `moderator?` probes decides whether the
roles pair lands at (1,2), (3,4), (4,5) or (7,8).  So the sets are DRIVABLE
with no declaration at all, provided the BASE already puts the decision at the
demanded ordinal.

This scan therefore selects, per gap-set, bases that
  (a) RECORD `(..._exists__<N>_exists == True)`  — the decision is at that
      ordinal in that run, which is the one thing the seeder cannot write, and
  (b) MINT every alias canonical the cube's other names live under, so the
      overlaid seed keys are real runtime keys and not inert canonicals,
ranked by how many of the cube's literals the base already matches.

usage: python3 _c20_exists_bases.py <cov.json> <dump_list> <out.json>
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
_CANON_RE = re.compile(r"SYM_RESULT_[A-Za-z0-9_]*?_(?:notifications|aspect_memberships|"
                       r"photos|tags|aspects|services|mentions)_[0-9a-f]{8}")
CUBES = None


def split_lits(nc):
    out = []
    for part in nc.split(" AND "):
        p, w = part.strip(), True
        if p.startswith("Not(") and p.endswith(")"):
            w, p = False, p[4:-1]
        out.append((p, w))
    return out


def _init(cubes):
    global CUBES
    CUBES = cubes


def work(path):
    try:
        evs, pcs, seeds, _v = parse(path)
    except Exception:
        return None
    amap = alias_map_for(evs, ALIASES)
    mint = set(amap.values())
    rn = renamer(amap)
    seen = {}
    for expr, taken, _s in pcs:
        seen.setdefault(fixlen(rn(expr)), set()).add(bool(taken))
    out = []
    for gi, (lits, canons, key) in enumerate(CUBES):
        if not canons <= mint:
            continue
        if key not in seen:                       # the ordinal context itself
            continue
        match = sum(1 for e, w in lits if e in seen and w in seen[e])
        confl = sum(1 for e, w in lits if e in seen and w not in seen[e])
        out.append((gi, match, confl))
    if not out:
        return None
    return (path, len(seeds), out)


def main():
    cov, lst, outp = sys.argv[1], sys.argv[2], sys.argv[3]
    miss = json.load(open(cov))["missing"]
    cubes, meta = [], []
    for i, m in enumerate(miss):
        if m["untracked"]:
            continue
        lits = split_lits(m["node_constraint"])
        ex = [e for e, _w in lits if "_exists__" in e]
        if not ex:
            continue
        key = ex[0]
        canons = set()
        for e, _w in lits:
            canons |= set(_CANON_RE.findall(e))
        cubes.append((lits, canons, key))
        meta.append({"missing_index": i, "width": len(lits), "exists_literal": key,
                     "exists_outcome": dict(lits)[key], "canonicals": sorted(canons)})
    print(f"exists gap-sets: {len(cubes)}")
    for j, mm in enumerate(meta):
        print(f"  g{j}: missing[{mm['missing_index']}] w={mm['width']} "
              f"{mm['exists_literal'][-46:]} = {mm['exists_outcome']}")
    files = open(lst).read().split()
    per = collections.defaultdict(list)
    with Pool(int(os.environ.get("JOBS", "3")), initializer=_init, initargs=(cubes,)) as pool:
        for n, r in enumerate(pool.imap_unordered(work, files, chunksize=64)):
            if r:
                path, ns, rows = r
                for gi, match, confl in rows:
                    per[gi].append({"path": path, "match": match, "conflict": confl,
                                    "nseeds": ns})
            if (n + 1) % 20000 == 0:
                print(f"  [{n+1}/{len(files)}] " +
                      " ".join(f"g{g}:{len(v)}" for g, v in sorted(per.items())), flush=True)
    res = {"meta": meta, "bases": {}}
    for gi in range(len(cubes)):
        rows = sorted(per.get(gi, []), key=lambda r: (-r["match"], r["conflict"], -r["nseeds"]))
        res["bases"][str(gi)] = rows[:120]
        w = len(cubes[gi][0])
        print(f"  g{gi}: {len(per.get(gi, []))} usable bases, best "
              f"{rows[0]['match'] if rows else 0}/{w} (conflict "
              f"{rows[0]['conflict'] if rows else '-'})")
    json.dump(res, open(outp, "w"), indent=1)
    print(f"C20-EXISTSBASES-DONE {outp}")


if __name__ == "__main__":
    main()
