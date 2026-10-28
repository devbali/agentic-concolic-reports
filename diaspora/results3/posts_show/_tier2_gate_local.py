#!/usr/bin/env python3
"""Batch-local driver for the ASSUMPTION GATE's IndependenceAssumption probe.

WHY THIS EXISTS — a defect in `src/`, NOT worked around silently (X10).
`assumption_checker.py` aborts the whole 83-probe suite on its FIRST posts_show
pair with

    File ".../assumption_checker.py", line 598, in test_declared
      fab = dict(fa); fab[db] = fb[db]
    KeyError: 'SYM_RESULT_..._records_photos_2c7fa358_row_text_empty'

The cause is a KEY-SPACE MISMATCH, one line wide:

  * `flipped_seeds(sd, seeds, expr, dim)` writes its flip at
    `rdim = _runtime_key(sd, dim)` — the RUNTIME ordinal name the runner
    actually seeds by (assumption_checker.py:~552).
  * `test_declared` then reads it back at `db` — the CANONICAL
    (statement-identified) name (assumption_checker.py:598).

`_runtime_key` is the identity only when nothing is aliased, so the flip-both
probe works on an endpoint whose dimensions are not ordinal-aliased (that is
why notifications' C7-A run never hit it) and raises KeyError on one that is.
posts_show canonicalizes every ordinal (`gate_canon:canonicalize_for_gate`), so
every one of its cross-rep pairs hits it.

The fix in `src/` is one line — `rdb = _runtime_key(sd, db); fab[rdb] = fb[rdb]`
— and is NOT made here: no `src/` change is authorized. This driver reproduces
`test_declared`'s IndependenceAssumption branch EXACTLY, with that single
correction, so the verdicts are the engine's own and not a reimplementation:
every helper (`expr_dimension`, `pick_snapshot_with`, `access_trace`,
`flipped_seeds`, `_reading_changed`, `trace_of`, `ProbeCache`) is imported from
the shipped module and called unchanged.

Second defect, also raised: one bad pair kills all 83. Each probe here is
isolated, so an exception is a per-probe ERROR verdict and the suite completes.
"""
import importlib, json, os, sys, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from end_to_end_completion_checker.assumption import assumption_checker as AC  # noqa: E402

MANIFEST = sys.argv[1]
DECLARED = sys.argv[2]
OUT = sys.argv[3]

cfg = json.load(open(MANIFEST))
if cfg.get("canonicalize"):
    mod_name, fn_name = cfg["canonicalize"].split(":")
    sys.path.insert(0, cfg["batch_dir"])
    mod = importlib.import_module(mod_name)
    AC._CANON_FN = getattr(mod, fn_name)
    AC._ALIASES = list(getattr(mod, "ALIASES", []) or [])
    print(f"[canonicalize] {cfg['canonicalize']} with {len(AC._ALIASES)} alias(es)", flush=True)

declared = json.load(open(DECLARED))
if "--limit" in sys.argv:
    declared = declared[: int(sys.argv[sys.argv.index("--limit") + 1])]
print(f"== tier2 gate (batch-local driver): {len(declared)} class representatives ==", flush=True)


def probe_independence(a, cache):
    """AC.test_declared's IndependenceAssumption branch, verbatim except for
    the two `_runtime_key` calls marked FIX."""
    batch = cfg["batch_dir"]
    ea, eb = a.get("expr_a", ""), a.get("expr_b", "")
    out = {"type": "IndependenceAssumption", "expr": ea, "expr_b": eb,
           "verdict": "?", "detail": "", "class": a.get("description", "")}
    da, db = AC.expr_dimension(ea), AC.expr_dimension(eb)
    if not da or not db:
        out.update(verdict="NOT-TESTABLE", detail="cannot derive seed dimensions from exprs")
        return out
    snap = AC.pick_snapshot_with(batch, [ea, eb], [da, db])
    if snap is None:
        missing = [e for e in (ea, eb) if AC.pick_snapshot_with(batch, [e], []) is None]
        if missing:
            out.update(verdict="NOT-TESTABLE",
                       detail="expr never recorded in the CURRENT corpus: " + missing[0][:80])
            return out
        out.update(verdict="PASS",
                   detail="mutually exclusive: both recorded, never co-evaluated in any run")
        return out
    sp, sd = snap
    scen = (sd.get("concolic_scenario") or {}).get("name")
    seeds = dict(sd.get("concolic_seeds") or {})
    base = set(AC.access_trace(sd))
    fa = AC.flipped_seeds(sd, seeds, ea, da)
    fb = AC.flipped_seeds(sd, seeds, eb, db)
    if fa is None or fb is None:
        out.update(verdict="NOT-TESTABLE", detail="cannot infer a flip value from the recorded PC")
        return out
    rdb = AC._runtime_key(sd, db)                      # FIX (see docstring)
    if rdb not in fb:                                  # FIX: flip-by-deletion
        fab = dict(fa)
        fab.pop(rdb, None)
    else:
        fab = dict(fa)
        fab[rdb] = fb[rdb]
    ra, rb, rab = (cache.run(x, scen, f"ind_{i}") for i, x in enumerate((fa, fb, fab)))
    if None in (ra, rb, rab):
        out.update(verdict="FAIL", detail="a flip probe produced no dump in the snapshot's scenario")
        return out
    for tag_, r_ in (("flip-A", ra), ("flip-B", rb), ("flip-both", rab)):
        for e_ in (ea, eb):
            why = AC._reading_changed(sd, r_, e_)
            if why:
                out.update(verdict="NOT-COMPARABLE", detail=f"{tag_}: {why}")
                return out
    covered = base | set(AC.trace_of(ra)) | set(AC.trace_of(rb))
    novel = set(AC.trace_of(rab)) - covered
    if novel:
        out.update(verdict="FAIL",
                   detail=f"combination (flip both) produced {len(novel)} target-call shape(s) "
                          f"absent from base/flip-A/flip-B: " +
                          "; ".join(f"{t} {n[:60]}" for t, n, _ in sorted(novel)[:3]))
    else:
        out.update(verdict="PASS",
                   detail=f"no combination-only access shapes (snapshot {os.path.basename(sp)})")
    return out


cache = AC.ProbeCache(cfg, False)
# pass 1 — derive every probe without launching the runner (AC's own protocol)
cache.planning = True
for a in declared:
    try:
        probe_independence(a, cache)
    except Exception:
        pass
cache.planning = False
print(f"  [{len(cache.wanted)} distinct probes needed for {len(declared)} assumptions]", flush=True)
cache.execute()

results = []
for a in declared:
    try:
        r = probe_independence(a, cache)
    except Exception as exc:
        r = {"type": "IndependenceAssumption", "expr": a.get("expr_a"),
             "expr_b": a.get("expr_b"), "verdict": "ERROR",
             "detail": f"{type(exc).__name__}: {exc}"[:200],
             "class": a.get("description", ""),
             "traceback": traceback.format_exc()[-600:]}
    results.append(r)
    print(f"  {r['verdict']:<15} {str(r['expr'])[:66]} || {str(r['expr_b'])[:46]}", flush=True)
    if r["detail"]:
        print(f"      {r['detail'][:170]}", flush=True)

json.dump(results, open(OUT, "w"), indent=1)
from collections import Counter
c = Counter(r["verdict"] for r in results)
print("\n=== TIER2 GATE SUMMARY ===")
for k, v in c.most_common():
    print(f"  {k:<16} {v}")
print(f"wrote {OUT}")
