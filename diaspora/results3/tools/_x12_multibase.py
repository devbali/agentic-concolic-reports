#!/usr/bin/env python3
"""X12 — MULTI-BASE probe of ANY derived gate test (generic).

`_c27_fals.py`'s base enumeration (notifications_index §39), generalised: every
derived test in `assumption_checker.py` builds its probe from ONE base --
`pick_snapshot_with`'s single richest snapshot recording the claim's exprs --
so a NOT-TESTABLE is an artefact of THAT base and a PASS is vouched by one
context only.  This runs the SHIPPED `test_declared` unchanged, once per base,
by pinning `pick_snapshot_with` at the pair's own query.

Class verdict = FAIL if ANY base FAILs (one run is the falsifier), else PASS if
any base PASSes, else the strongest non-vouching verdict reached.

  usage: [X12_K=8] [X12_ACTIVE=0] python3 _x12_multibase.py <batchdir> <classes.json> <out.json>

X12_ACTIVE=0 stubs ConfinementAssumption's (vi)/(vii) active search, which is
base-INDEPENDENT (a function of the decision and the corpus, never of the
composition base); a PASS is then reported as PASS(base-dependent) and covers
criteria (i)-(v),(viii) only.  X12_ACTIVE=1 runs them.
"""
import array, collections, json, os, sys

sys.path.insert(0, "/home/dev/project/src")
BATCH = os.path.abspath(sys.argv[1])
CLASSES, OUT = sys.argv[2], sys.argv[3]
sys.path.insert(0, BATCH)
from end_to_end_completion_checker.assumption import assumption_checker as A

K = int(os.environ.get("X12_K", "8"))
ACTIVE = os.environ.get("X12_ACTIVE", "0") == "1"
cfg = json.load(open(os.path.join(BATCH, "assumption_manifest.json")))
classes = json.load(open(CLASSES))
if isinstance(classes, dict):
    classes = classes.get("assumptions") or []

if cfg.get("canonicalize"):
    import importlib
    mod_name, fn_name = cfg["canonicalize"].split(":")
    mod = importlib.import_module(mod_name)
    A._CANON_FN = getattr(mod, fn_name)
    A._ALIASES = [A.AliasAssumption(result_pattern=a.get("result_pattern", ""),
                                    key=a.get("key", "statement"), k=int(a.get("k", 1)))
                  for a in classes
                  if a.get("type") in ("AliasAssumption", "DecisionAliasAssumption")] \
        or list(getattr(mod, "ALIASES", []) or [])
    print(f"[canonicalize] {cfg['canonicalize']} with {len(A._ALIASES)} alias(es)", flush=True)

# match the gate's checkpoint phase keys (they hash the DECLARED set)
if os.environ.get("X12_DECLARED_FOR_KEY"):
    A._DECLARED_DIGEST = A._ckpt.digest(json.load(open(os.environ["X12_DECLARED_FOR_KEY"])))

rows = A.corpus_index(BATCH)
post = A._postings(BATCH)
print(f"[index] {len(rows)} dumps  K={K}  ACTIVE={ACTIVE}  classes={len(classes)}", flush=True)

if not ACTIVE:
    A._exhaustive_flip = lambda *a_, **k_: (None, "")
    A._constructed_route = lambda *a_, **k_: (None, "")


def exprs_of(a):
    if a.get("expr_a") or a.get("expr_b"):
        return [e for e in (a.get("expr_a"), a.get("expr_b")) if e]
    e = [a.get("expr")] if a.get("expr") else []
    return e + [g for g, _o in (a.get("conditioning") or a.get("gates") or [])]


def candidates(exprs, k):
    """Up to k base rows recording every expr, scenario-diverse, richest
    first. `_c27_fals.py::candidates`, verbatim."""
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
plans = []
for ci, a in enumerate(classes):
    ex = exprs_of(a)
    if not ex:
        a["_n_candidate_bases"] = 0
        continue
    bases, total = candidates(ex, K)
    a["_n_candidate_bases"] = total
    a["_probe_exprs"] = ex
    for b in bases:
        plans.append((ci, b[2]))
print(f"[plan] {len(plans)} (class, base) plan(s)", flush=True)


def pinned(path, want):
    def f(b, exprs, dims):
        if frozenset(A.canon(e) for e in exprs) == want:
            return (path, A.load_dump(path))
        return REAL_PSW(b, exprs, dims)
    return f


def run_pass(cache):
    res = collections.defaultdict(list)
    for ci, bp in plans:
        a = classes[ci]
        A.pick_snapshot_with = pinned(bp, frozenset(A.canon(e) for e in a["_probe_exprs"]))
        try:
            out = A.test_declared(cfg, a, cache)
        except Exception as exc:
            out = {"verdict": "ERROR", "detail": f"{type(exc).__name__}: {exc}"[:200]}
        finally:
            A.pick_snapshot_with = REAL_PSW
        if not cache.planning:
            v = out.get("verdict") or "ERROR"
            if v == "PASS" and not ACTIVE and a.get("type") == "ConfinementAssumption":
                v = "PASS(base-dependent)"
            res[ci].append((v, os.path.basename(bp), (out.get("detail") or "")[:200]))
    return res


cache = A.ProbeCache(cfg, keep=False)
cache.planning = True
run_pass(cache)
cache.planning = False
print(f"[probes] {len(cache.wanted)} distinct probe(s) wanted", flush=True)
cache.execute()
results = run_pass(cache)
cache.close()

RANK = {"FAIL": 0, "PASS": 1, "PASS(base-dependent)": 1, "NOT-COMPARABLE": 2,
        "NOT-TESTABLE": 3, "ERROR": 4}
out, tally, moved = [], collections.Counter(), collections.Counter()
for ci, a in enumerate(classes):
    rs = results.get(ci, [])
    verdict = min((r[0] for r in rs), key=lambda v: RANK.get(v, 5)) if rs else "NOT-TESTABLE"
    tally[verdict] += 1
    moved[(a.get("_shipped_verdict"), verdict)] += 1
    out.append({"class": ci, "type": a.get("type"), "shipped": a.get("_shipped_verdict"),
                "verdict": verdict, "expr_a": a.get("expr_a") or a.get("expr"),
                "expr_b": a.get("expr_b"), "covers": a.get("_covers"),
                "candidate_bases_in_corpus": a.get("_n_candidate_bases"),
                "bases_probed": len(rs),
                "bases_realising": sum(1 for v, _b, _d in rs if v not in ("NOT-TESTABLE", "ERROR")),
                "per_base": [{"verdict": v, "base": b, "detail": d} for v, b, d in rs]})
json.dump(out, open(OUT, "w"), indent=1)

print()
for o in out:
    pb = collections.Counter(x["verdict"] for x in o["per_base"])
    print(f"  [{o['class']:03d}] {str(o['shipped']):<14} -> {o['verdict']:<20} "
          f"bases {o['bases_probed']:>2}/{o['candidate_bases_in_corpus']:<6} "
          f"realising {o['bases_realising']:>2}  {dict(pb)}")
print()
print("X12 RESULT: " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items())))
print("X12 MOVES:")
for (s, v), n in sorted(moved.items(), key=lambda kv: -kv[1]):
    same = (s == v) or (s == "PASS" and v == "PASS(base-dependent)")
    print(f"   {n:5d}  {s} -> {v}" + ("   (unchanged)" if same else "   *** MOVED ***"))
print("X12-DONE")
