#!/usr/bin/env python3
"""C22 — per-KEY realisation report for a constructed drive.

`_c20_realised.py` reads C20's manifest shape (`gap` / `missing_index`); this
reads C22's (`{meta, stats, manifest}`) and answers the RUNBOOK's Phase-2
question — "explain the round per key (honoured / contradicted / never
evaluated)" — over every run the drive produced.

  HONOURED     the run recorded the member with the demanded outcome
  CONTRADICTED the run recorded it with the other outcome
  UNEVALUATED  the run never evaluated it

usage: python3 _c22_realised.py <manifest.json> <TAG>
"""
import json, os, re, sys, glob, collections
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer      # noqa: E402
from coverage_assumptions import ALIASES                             # noqa: E402
from _c20_scan2 import parse                                         # noqa: E402
from _c22_round1 import fixlen, _SELFCMP, split_lits                 # noqa: E402

SETS = None


def _init(sets):
    global SETS
    SETS = sets


def work(path):
    try:
        evs, pcs, _s, _v = parse(path)
    except Exception:
        return None
    amap = alias_map_for(evs, ALIASES)
    rn = renamer(amap)
    seen = {}
    for expr, taken, _st in pcs:
        e = rn(expr)
        if amap:
            e = _SELFCMP.sub(r"(\1 == \1__prior)", e)
        seen.setdefault(fixlen(e), set()).add(bool(taken))
    out = []
    for si, members in enumerate(SETS):
        out.append(tuple((("B" if len(seen[e]) > 1 else ("T" if True in seen[e] else "F"))
                          if e in seen else "U") for e in members))
    return (os.path.basename(path), out)


def main():
    manp, tag = sys.argv[1], sys.argv[2]
    blob = json.load(open(manp))
    meta, man = blob["meta"], blob["manifest"]
    sets = [m["members"] for m in meta]
    byname = {}
    for r in man:
        byname.setdefault((r["set"], tuple(r["assignment"])), []).append(r["base"])
    files = sorted(glob.glob(os.path.join(HERE, f"dump_*_{tag}*.json")))
    print(f"driven dumps {len(files)}; gap-sets {len(sets)}; targeted leaves {len(byname)}")
    obs_all = []
    with Pool(int(os.environ.get("JOBS", "2")), initializer=_init, initargs=(sets,)) as pool:
        for r in pool.imap_unordered(work, files, chunksize=16):
            if r:
                obs_all.append(r)
    print(f"parsed {len(obs_all)} driven dumps")
    for si, members in enumerate(sets):
        targets = sorted(k[1] for k in byname if k[0] == si)
        realised = set()
        key = collections.defaultdict(collections.Counter)
        for _n, obs in obs_all:
            o = obs[si]
            if "U" in o:
                continue
            walked = set()
            for a in targets:
                if all(o[j] in ("B", "T" if a[j] else "F") for j in range(len(members))):
                    walked.add(a)
            realised |= walked
        # per key, over the runs that evaluated the set at all
        for _n, obs in obs_all:
            o = obs[si]
            for j, e in enumerate(members):
                if o[j] == "U":
                    key[e]["UNEVALUATED"] += 1
                else:
                    key[e]["EVALUATED"] += 1
                    if o[j] == "B":
                        key[e]["BOTH"] += 1
        print(f"\n  set{si}: targeted {len(targets)} leaves, "
              f"REALISED {len(realised)}/{len(targets)}")
        for e in members:
            c = key[e]
            tot = c["EVALUATED"] + c["UNEVALUATED"]
            print(f"      eval {c['EVALUATED']:5d}/{tot:5d}  both {c['BOTH']:5d}  {e[:100]}")
        for a in targets:
            if a not in realised:
                print(f"      NOT REALISED: {''.join('T' if x else 'F' for x in a)}")
    print("C22-REALISED-DONE")


if __name__ == "__main__":
    main()
