#!/usr/bin/env python3
"""C29 step 1 — whole-corpus bitset census of the DISPATCH family.

Same reading as `_c25_mincond.py` (alias_map_for -> CR.canonicalize_ordinals ->
fixlen), but the expr universe is DISCOVERED rather than given: every canonical
path-condition expression matching FILTER is kept, so nothing that mentions the
dispatch variable, the `3aa8587a` / `10254800` to_ary row chains, the photos
collection or the principal's person chain can be missed.

Per dump it also records the drive tag, the scenario and the SEEDED value of
SYM_NOTE_TYPE_PROFILE, so the census can be cut by how the run was produced.

  usage: DUMP_LIST=.. OUT=.. [WORKERS=14] [SCAN_FILTER=regex] python3 -u _c30_scan.py
Read-only.
"""
import json, os, pickle, re, sys, time
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for            # noqa: E402
import coverage_report as CR                                     # noqa: E402
from coverage_assumptions import ALIASES                         # noqa: E402

LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_c29_R1.txt"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_c30_scan.pkl"))
WORKERS = int(os.environ.get("WORKERS", "14"))

# C30: the expr universe is NOT narrowed to C29's dispatch family. C29's
# FILTER was written for one investigation (the `SYM_NOTE_TYPE_PROFILE` cubes)
# and silently drops every expression outside it — which is exactly the kind of
# instrument that returns a clean zero because it matched nothing. This round
# has to reason about whatever the OFF pass reports blocking, so the default is
# EVERYTHING and the narrowing, if any, is passed in explicitly.
FILTER = re.compile(os.environ.get("SCAN_FILTER", "."))
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
_TAG = re.compile(r"^dump_(.+?)_dse\d+_(.+)\.json$")

FILES = [l.strip() for l in open(LIST) if l.strip()]
N = len(FILES)
CHUNK = 500


def scan(args):
    lo, hi = args
    T, F = {}, {}          # expr -> dict(local_index -> True)
    meta = []
    for i in range(lo, hi):
        p = FILES[i]
        li = i - lo
        try:
            d = json.load(open(p))
        except Exception:
            meta.append(("", "", None, 0))
            continue
        ev = d.get("events") or ()
        alias_map_for([(e.get("result_name"), e.get("note"))
                       for e in ev if e.get("type") == "symbolic_call"], ALIASES)
        CR.canonicalize_ordinals(d)
        seeds = d.get("concolic_seeds") or {}
        pv = seeds.get("SYM_NOTE_TYPE_PROFILE")
        sc = (d.get("concolic_scenario") or {}).get("name") or ""
        m = _TAG.match(os.path.basename(p))
        npc = 0
        for e in d.get("events") or ():
            if e.get("type") != "path_condition":
                continue
            npc += 1
            x = fixlen(str(e.get("expr", "")))
            if not FILTER.search(x):
                continue
            (T if e.get("taken") else F).setdefault(x, set()).add(li)
        meta.append((m.group(2) if m else "", sc, pv, npc))
        del d
    return lo, hi - lo, T, F, meta


if __name__ == "__main__":
    ranges = [(lo, min(lo + CHUNK, N)) for lo in range(0, N, CHUNK)]
    TB, FB = {}, {}
    META = [None] * N
    t0 = time.time(); done = 0
    with Pool(WORKERS) as pool:
        for lo, n, Tc, Fc, meta in pool.imap_unordered(scan, ranges, chunksize=1):
            for src, dst in ((Tc, TB), (Fc, FB)):
                for x, s in src.items():
                    v = dst.get(x, 0)
                    for li in s:
                        v |= 1 << (lo + li)
                    dst[x] = v
            META[lo:lo + n] = meta
            done += n
            if done % 20000 < CHUNK:
                print(f"  {done}/{N}  {time.time()-t0:.0f}s", flush=True)
    print(f"scan done {time.time()-t0:.0f}s  exprs={len(set(TB) | set(FB))}", flush=True)
    pickle.dump({"n": N, "files": FILES, "T": TB, "F": FB, "meta": META,
                 "list": LIST}, open(OUT, "wb"), 4)
    print("C29-SCAN-DONE", flush=True)
