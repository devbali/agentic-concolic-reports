#!/usr/bin/env python3
"""P15 — corpus index + observed domain, built ONCE and pickled.

Everything downstream (classification, base choice, seed construction) joins
CHECKER-side names to DUMP-side ones. The RUNBOOK's `len` rule (Phase 2) says
that join must be done in BOTH directions or it fails silently as "never
evaluated" / "no compatible base". This module does it the only way that
cannot drift: it pushes every dump-side seed key THROUGH the same two
transforms the checker's loader applies (alias canonicalization, then
`len(X) -> SYM_LEN_X`) and records the resulting checker name, so the reverse
map is derived, never guessed.

Writes a pickle: {"exprs": [...], "dumps": [...], "domain": {...}}
  dumps[i] = (path, variant, eval_mask, true_mask, nseeds)
"""
import json, os, pickle, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402

_LEN_RE = re.compile(r"len\(([^()]+)\)")
VARIANTS = ("auth_html", "anon_html", "auth_json", "anon_json")
OUT = os.environ.get("P15_INDEX", os.path.join(HERE, "_p15_index.pkl"))
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_pruned_OD0911.txt"))
PARTS = os.environ.get("PARTS_IN", os.path.join(HERE, "_parts_OD0911.json"))


def fixlen(s):
    return _LEN_RE.sub(r"SYM_LEN_\1", s) if s else s


def main():
    parts = json.load(open(PARTS))["parts"]
    exprs = sorted({m for p in parts for m in p["members"]})
    eidx = {e: i for i, e in enumerate(exprs)}
    print(f"expr universe: {len(exprs)}", flush=True)

    files = [l.strip() for l in open(LIST) if l.strip()]
    files = [f if os.path.isabs(f) else os.path.join(HERE, f) for f in files]
    print(f"dumps: {len(files)}  from {os.path.basename(LIST)}", flush=True)

    dumps = []
    canon_idx = {}
    seedable = Counter()
    domain = defaultdict(Counter)
    raw = {}
    t0 = time.time()
    for n, p in enumerate(files):
        if n and n % 2500 == 0:
            print(f"  {n}/{len(files)}  {time.time()-t0:.0f}s", flush=True)
        try:
            d = json.load(open(p))
        except Exception:
            continue
        ev = d.get("events") or ()
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in ev if e.get("type") == "symbolic_call"], ALIASES)
        rn = renamer(amap)
        cm = 0
        for c in set((amap or {}).values()):
            j = canon_idx.setdefault(c, len(canon_idx))
            cm |= 1 << j
        em = tm = 0
        for e in ev:
            if e.get("type") != "path_condition":
                continue
            i = eidx.get(fixlen(rn(str(e.get("expr", "")))))
            if i is None:
                continue
            em |= 1 << i
            if e.get("taken"):
                tm |= 1 << i
        for sv in d.get("symbolic_vars") or ():
            nm, val = sv.get("name"), sv.get("value")
            if nm is None or isinstance(val, (dict, list)):
                continue
            nm = fixlen(rn(nm))
            r = repr(val)
            domain[nm][r] += 1
            raw.setdefault((nm, r), val)
        for sk in d.get("concolic_seeds") or ():
            seedable[fixlen(rn(sk))] += 1
        base = os.path.basename(p)
        v = next((x for x in VARIANTS if base.startswith("dump_" + x)), "auth_html")
        dumps.append((p, v, em, tm, len(d.get("concolic_seeds") or {}), cm))
        del d
    print(f"indexed {len(dumps)} dumps in {time.time()-t0:.0f}s; "
          f"{len(domain)} variables in the observed domain; "
          f"{len(seedable)} seedable checker names; "
          f"{len(canon_idx)} alias canonicals", flush=True)
    with open(OUT, "wb") as fh:
        pickle.dump({"exprs": exprs, "dumps": dumps, "seedable": dict(seedable),
                     "canon": [c for c, _ in sorted(canon_idx.items(), key=lambda kv: kv[1])],
                     "domain": {k: dict(v) for k, v in domain.items()},
                     "raw": {f"{k[0]}\x00{k[1]}": v for k, v in raw.items()}}, fh, 4)
    print(f"P15-INDEX-DONE {OUT} ({os.path.getsize(OUT)/1e6:.1f} MB)", flush=True)


main()
