#!/usr/bin/env python3
"""C13 — corpus index over the C12 snapshot, built ONCE and pickled.

Every downstream join is CHECKER-side name -> DUMP-side name. The RUNBOOK's
`len` rule says that join must be done in both directions or it fails silently
as "never evaluated" / "no compatible base" (posts_show §77.4: three defects of
exactly that shape). This module does not guess the reverse map: it pushes every
dump-side key through the SAME transforms the checker's loader applies
(coverage_report.canonicalize_ordinals, then len(X) -> SYM_LEN_X) and records
what comes out, so a name the corpus cannot seed is COUNTED, never dropped.

writes a pickle: exprs, dumps[(path, variant, eval_mask, true_mask, nseeds,
canon_mask)], domain, raw, seedable, canon
"""
import json, os, pickle, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
import coverage_report as CR                                     # noqa: E402
from coverage_assumptions import ALIASES                         # noqa: E402

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")

GAPS = os.environ.get("C13_GAPS", os.path.join(HERE, "_c13_gaps.json"))
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_pruned_20260911_143539.txt"))
OUT  = os.environ.get("C13_INDEX", os.path.join(HERE, "_c13_index.pkl"))
LIMIT = int(os.environ.get("LIMIT", "0"))

gaps = json.load(open(GAPS))
exprs = sorted({e for g in gaps for e, _ in g["cube"]})
eidx = {e: i for i, e in enumerate(exprs)}
print(f"expr universe: {len(exprs)}", flush=True)

files = [l.strip() for l in open(LIST) if l.strip()]
if LIMIT:
    files = files[::max(1, len(files) // LIMIT)][:LIMIT]
print(f"dumps: {len(files)} from {os.path.basename(LIST)}", flush=True)

dumps, canon_idx = [], {}
seedable, domain, raw = Counter(), defaultdict(Counter), {}
t0 = time.time()
for n, p in enumerate(files):
    if n and n % 10000 == 0:
        print(f"  {n}/{len(files)}  {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(p))
    except Exception:
        continue
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    # the loader's own transform (rename + split_self_compare), in place
    CR.canonicalize_ordinals(d)
    rn = renamer(amap)
    cm = 0
    for c in set((amap or {}).values()):
        cm |= 1 << canon_idx.setdefault(c, len(canon_idx))
    em = tm = 0
    for e in d.get("events") or ():
        if e.get("type") != "path_condition":
            continue
        i = eidx.get(fixlen(str(e.get("expr", ""))))
        if i is None:
            continue
        em |= 1 << i
        if e.get("taken"):
            tm |= 1 << i
    for sv in d.get("symbolic_vars") or ():
        nm, val = sv.get("name"), sv.get("value")
        if nm is None or isinstance(val, (dict, list)):
            continue
        nm = fixlen(nm)
        r = repr(val)
        domain[nm][r] += 1
        raw.setdefault((nm, r), val)
    ns = 0
    for sk in d.get("concolic_seeds") or ():
        seedable[fixlen(rn(sk))] += 1
        ns += 1
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), "html_plain")
    dumps.append((p, v, em, tm, ns, cm))
    del d
print(f"indexed {len(dumps)} dumps in {time.time()-t0:.0f}s; "
      f"{len(domain)} domain variables; {len(seedable)} seedable checker names; "
      f"{len(canon_idx)} alias canonicals", flush=True)
with open(OUT, "wb") as fh:
    pickle.dump({"exprs": exprs, "dumps": dumps, "seedable": dict(seedable),
                 "canon": [c for c, _ in sorted(canon_idx.items(), key=lambda kv: kv[1])],
                 "domain": {k: dict(v) for k, v in domain.items()},
                 "raw": {f"{k[0]}\x00{k[1]}": v for k, v in raw.items()}}, fh, 4)
print(f"C13-INDEX-DONE {OUT} ({os.path.getsize(OUT)/1e6:.1f} MB)", flush=True)
