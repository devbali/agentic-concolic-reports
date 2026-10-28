#!/usr/bin/env python3
"""X12 — MULTI-BASE probe of `_test_confinement` (DISCIPLINE §16c check 2).

WHY. `_c27_fals.py` (notifications_index §39) showed that
`_test_conjunction_foreclosure` builds its probe from ONE base --
`pick_snapshot_with`'s single richest snapshot -- so a NOT-TESTABLE is an
artefact of that base, not evidence about the claim, and a PASS is vouched by
one context only. `_test_confinement` selects its composition base the SAME
way (`pick_snapshot_with(batch, [ea, eb], [da, db])`), so criteria (i)-(v) and
(viii) -- flip-A / flip-B / flip-both -- are single-base too. Criterion (vi)
`_exhaustive_flip` IS multi-base (one representative per outcome profile), and
(vi)/(vii) do NOT depend on the composition base at all.

WHAT. `_c27_fals.py`'s base enumeration, verbatim in semantics, applied to the
confinement test: for each class enumerate EVERY dump recording both members,
rank by seed richness with scenario diversity first, take up to K, and run the
SHIPPED `_test_confinement` body once per base by pointing
`pick_snapshot_with` at that base. Nothing in the test is rewritten.

  X12_ACTIVE=0 (default)  stub (vi)/(vii) -- they are base-INDEPENDENT, so
                          for a class the gate already PASSed they cannot
                          change, and for a class the gate returned
                          NOT-TESTABLE on they were never reached.  A verdict
                          of PASS under the stub is reported as
                          "PASS(i-v,viii)" -- base-dependent criteria only.
  X12_ACTIVE=1            run them for real (cost: the full active search).

Class verdict = FAIL if any base FAILs (one run is the falsifier), else PASS
if any base PASSes, else the strongest non-vouching verdict reached.

  usage: [X12_K=8] [X12_ACTIVE=0] python3 _x12_conf_multibase.py <classes.json> <out.json>
"""
import array, collections, json, os, sys

sys.path.insert(0, "/home/dev/project/src")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from end_to_end_completion_checker.assumption import assumption_checker as A

CLASSES = sys.argv[1]
OUT = sys.argv[2]
K = int(os.environ.get("X12_K", "8"))
ACTIVE = os.environ.get("X12_ACTIVE", "0") == "1"

cfg = json.load(open(os.path.join(HERE, "assumption_manifest.json")))
classes = json.load(open(CLASSES))

import importlib
mod_name, fn_name = cfg["canonicalize"].split(":")
mod = importlib.import_module(mod_name)
A._CANON_FN = getattr(mod, fn_name)
A._ALIASES = list(getattr(mod, "ALIASES", []) or [])
print(f"[canonicalize] {cfg['canonicalize']} with {len(A._ALIASES)} alias(es)", flush=True)

batch = cfg["batch_dir"]
rows = A.corpus_index(batch)
post = A._postings(batch)
print(f"[index] {len(rows)} dumps  K={K}  ACTIVE={ACTIVE}", flush=True)

if not ACTIVE:
    # (vi)/(vii) are functions of the DECISION and the corpus, never of the
    # composition base; stubbing them isolates the base-dependent criteria.
    A._exhaustive_flip = lambda *a_, **k_: (None, "")
    A._constructed_route = lambda *a_, **k_: (None, "")


def candidates(exprs, k):
    """Up to k base rows recording every expr, scenario-diverse, richest first.
    `_c27_fals.py::candidates`, verbatim."""
    ce = [A.canon(e) for e in exprs]
    empty = array.array("i")
    walk = min(((post.get(e) or (empty,))[0] for e in ce), key=len)
    hits = []
    for i in walk:
        p, seeds, scen, recorded = rows[i]
        if all(e in recorded for e in ce):
            hits.append((len(seeds), i, p, seeds, scen))
    hits.sort(key=lambda t: -t[0])
    by_scen, out = collections.defaultdict(list), []
    for h in hits:
        by_scen[h[4]].append(h)
    while len(out) < k and any(by_scen.values()):
        for sc in sorted(by_scen):
            if by_scen[sc] and len(out) < k:
                out.append(by_scen[sc].pop(0))
    return out, len(hits)


REAL_PSW = A.pick_snapshot_with

plans = []           # (class_idx, base_idx, base_path)
for ci, a in enumerate(classes):
    bases, total = candidates([a["expr_a"], a["expr_b"]], K)
    a["_n_candidate_bases"] = total
    for bi, b in enumerate(bases):
        plans.append((ci, bi, b[2]))
print(f"[plan] {len(plans)} (class, base) probe plan(s) over {len(classes)} class(es)", flush=True)


def pinned(path, ea, eb):
    """`pick_snapshot_with` pinned to ONE base for the pair's own query only;
    every other query (notably `_route_construction`'s) falls through."""
    want = frozenset((A.canon(ea), A.canon(eb)))
    def f(b, exprs, dims):
        if frozenset(A.canon(e) for e in exprs) == want:
            return (path, A.load_dump(path))
        return REAL_PSW(b, exprs, dims)
    return f


def run_pass(cache):
    res = collections.defaultdict(list)
    for ci, bi, bp in plans:
        a = classes[ci]
        A.pick_snapshot_with = pinned(bp, a["expr_a"], a["expr_b"])
        out = {"type": a["type"], "expr": a["expr_a"], "expr_b": a["expr_b"],
               "verdict": "", "detail": ""}
        try:
            A._test_confinement(cfg, a, cache, out)
        except Exception as exc:
            out.update(verdict="ERROR", detail=f"{type(exc).__name__}: {exc}"[:200])
        finally:
            A.pick_snapshot_with = REAL_PSW
        if not cache.planning:
            v = out["verdict"] or "ERROR"
            if v == "PASS" and not ACTIVE:
                v = "PASS(i-v,viii)"
            res[ci].append((v, os.path.basename(bp), out["detail"][:200]))
    return res


cache = A.ProbeCache(cfg, keep=False)
cache.planning = True
run_pass(cache)
cache.planning = False
print(f"[probes] {len(cache.wanted)} distinct probe(s) wanted", flush=True)
cache.execute()
results = run_pass(cache)
cache.close()

RANK = {"FAIL": 0, "PASS": 1, "PASS(i-v,viii)": 1, "NOT-COMPARABLE": 2,
        "NOT-TESTABLE": 3, "ERROR": 4}
out, tally = [], collections.Counter()
for ci, a in enumerate(classes):
    rs = results.get(ci, [])
    verdict = min((r[0] for r in rs), key=lambda v: RANK[v]) if rs else "NOT-TESTABLE"
    tally[verdict] += 1
    out.append({"class": ci, "shipped": a.get("_shipped_verdict"),
                "verdict": verdict, "expr_a": a["expr_a"], "expr_b": a["expr_b"],
                "covers": a.get("_covers"),
                "candidate_bases_in_corpus": a.get("_n_candidate_bases"),
                "bases_probed": len(rs),
                "bases_realising": sum(1 for v, _b, _d in rs
                                       if v not in ("NOT-TESTABLE", "ERROR")),
                "per_base": [{"verdict": v, "base": b, "detail": d} for v, b, d in rs]})
json.dump(out, open(OUT, "w"), indent=1)

print()
moved = collections.Counter()
for o in out:
    pb = collections.Counter(x["verdict"] for x in o["per_base"])
    moved[(o["shipped"], o["verdict"])] += 1
    print(f"  [{o['class']:03d}] {str(o['shipped']):<14} -> {o['verdict']:<14} "
          f"bases {o['bases_probed']:>2}/{o['candidate_bases_in_corpus']:<6} {dict(pb)}")
print()
print("X12 RESULT: " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items())))
print("X12 MOVES:")
for (s, v), n in sorted(moved.items(), key=lambda kv: -kv[1]):
    print(f"   {n:4d}  {s} -> {v}" + ("   (UNCHANGED)" if s == v or
          (s == "PASS" and v == "PASS(i-v,viii)") else "   *** MOVED ***"))
print("X12-DONE")
