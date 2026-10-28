#!/usr/bin/env python3
"""P29 — the corpus DECISION MATRIX, one scan.

Per run of the pruned corpus, record for every canonicalized+fixlen decision
expression a 2-bit mask (1 = taken False seen, 2 = taken True seen), plus the
set of MINTED canonical result names and the run's label. Everything the
mechanism analysis of steps 1-3 needs is derivable from this in memory.

Writes `_p29_decmatrix.pkl`:  {"exprs":[...], "rows":[{"m":{idx:mask}, "p":path}]}
"""
import json, os, re, sys, pickle, time
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer     # noqa
from coverage_assumptions import ALIASES                            # noqa

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s


def one(path):
    try:
        d = json.load(open(path))
    except Exception:
        return None
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rn = renamer(amap)
    dec = {}
    for e in ev:
        if e.get("type") == "path_condition":
            k = fixlen(rn(str(e.get("expr", ""))))
            dec[k] = dec.get(k, 0) | (2 if e.get("taken") else 1)
    minted = set()
    for e in ev:
        if e.get("type") == "symbolic_call":
            r = e.get("result_name")
            if r:
                minted.add(amap.get(r, r))
    return dec, sorted(minted), os.path.basename(path)


def main():
    lst = sys.argv[1] if len(sys.argv) > 1 else HERE + "/_snapshot_pruned_P26F2.txt"
    paths = [l.strip() for l in open(lst) if l.strip()]
    print("dumps:", len(paths), flush=True)
    eidx, elist = {}, []
    midx, mlist = {}, []
    rows = []
    bad = 0
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=int(os.environ.get("W", "2"))) as ex:
        for i, r in enumerate(ex.map(one, paths, chunksize=200)):
            if r is None:
                bad += 1; continue
            dec, minted, name = r
            m = {}
            for k, v in dec.items():
                j = eidx.get(k)
                if j is None:
                    j = eidx[k] = len(elist); elist.append(k)
                m[j] = v
            mm = []
            for k in minted:
                j = midx.get(k)
                if j is None:
                    j = midx[k] = len(mlist); mlist.append(k)
                mm.append(j)
            rows.append((m, mm, name))
            if (i + 1) % 10000 == 0:
                print("  ..", i + 1, "%.0fs" % (time.time() - t0),
                      "exprs", len(elist), "minted", len(mlist), flush=True)
    out = HERE + "/_p29_decmatrix.pkl"
    with open(out, "wb") as f:
        pickle.dump({"exprs": elist, "minted": mlist, "rows": rows,
                     "n": len(paths), "bad": bad}, f, protocol=4)
    print("distinct decision exprs:", len(elist))
    print("distinct minted canonicals:", len(mlist))
    print("unparseable:", bad)
    print("wrote", out, "%.1f MB" % (os.path.getsize(out) / 1e6))
    print("P29-DECMATRIX-DONE")


main()
