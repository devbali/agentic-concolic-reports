#!/usr/bin/env python3
"""C27 — ACTIVE FALSIFICATION of the 24 §16g WELL-FOUNDED DROP classes.

WHY. The shipped derived test (`_test_subconjunction_foreclosure`, which §16g
rides on unchanged) returned NOT-TESTABLE on 24 of 24 classes on 2026-09-14:
its base is the ONE richest snapshot that records the member together with
every literal of `C`, and the flips it derives from that single base were not
REALISED by the app ("seeding is not realising, so it cannot vouch"). Per
DISCIPLINE §24.4 a NOT-TESTABLE is not a licence, and the campaign's own
precedent for that situation (§31.2 RE-MINT-IDENTITY, §31.3
GATE-CONJ-INFEASIBLE) is to run an ACTIVE FALSIFICATION in the gate's place
and record it.

WHAT. The same probe, from MANY bases instead of one. For each class we
enumerate EVERY dump of the corpus that records `d` and all of `C`, rank them
by seed richness, take up to K per class with scenario diversity first, derive
the same flips the shipped test derives, and replay. The verdict rule is the
shipped one, per base:

    FAIL           the replay REALISES every literal of C and RECORDS d
                   -> the §16g drop for that class is REFUTED
    PASS           the replay realises C and does not record d
    NOT-COMPARABLE a flip changed what an aliased ordinal resolved to
    NOT-TESTABLE   the replay did not realise C (or no flip could be inferred)

A class is PASS if any base passes, FAIL if any base fails (a single run is
the falsifier), otherwise the strongest non-vouching verdict it reached.

Read-only with respect to src/ and to the corpus: probe dumps are drained by
`run_probe` exactly as the gate drains them (keep=False).

  usage: [FALS_K=8] python3 _c27_fals.py <classes.json> <out.json>
"""
import collections, json, os, sys

sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from end_to_end_completion_checker.assumption import assumption_checker as A

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSES = sys.argv[1]
OUT = sys.argv[2]
K = int(os.environ.get("FALS_K", "8"))

cfg = json.load(open(os.path.join(HERE, "assumption_manifest.json")))
classes = json.load(open(CLASSES))

# --- install the canonicalize hook exactly as main() does, BEFORE any
# --- ProbeCache exists (the cache asserts this) and with the SAME alias list
# --- the C27 gate ran under, so `_canon_key` -- and therefore the corpus
# --- index checkpoint -- is the same one and resumes instead of rebuilding.
import importlib
mod_name, fn_name = cfg["canonicalize"].split(":")
mod = importlib.import_module(mod_name)
A._CANON_FN = getattr(mod, fn_name)
A._ALIASES = list(getattr(mod, "ALIASES", []) or [])
print(f"[canonicalize] {cfg['canonicalize']} with {len(A._ALIASES)} alias(es)", flush=True)

batch = cfg["batch_dir"]
rows = A.corpus_index(batch)
post = A._postings(batch)
print(f"[index] {len(rows)} dumps", flush=True)


def candidates(exprs, k):
    """Up to k base rows recording every expr, scenario-diverse, richest first."""
    ce = [A.canon(e) for e in exprs]
    import array
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
    # round-robin over scenarios, richest first within each
    while len(out) < k and any(by_scen.values()):
        for sc in sorted(by_scen):
            if by_scen[sc] and len(out) < k:
                out.append(by_scen[sc].pop(0))
    return out, len(hits)


def build(a, base):
    """(seeds, scenario, base_path, base_dump, n_flipped) or (None, why)."""
    _n, _i, p, _seeds, _scen = base
    sd = A.load_dump(p)
    scen = (sd.get("concolic_scenario") or {}).get("name")
    seeds = dict(A.seeds_as_written(sd))
    gates = [(g, side == "taken") for g, side in a["conditioning"]]
    nflip = 0
    for g, o in gates:
        if o in A.outcomes_of(sd, g):
            continue
        dim = A.expr_dimension(g)
        if not dim:
            return None, f"no seed dimension for {g[:60]}"
        nxt = A.flipped_seeds(sd, seeds, g, dim)
        if nxt is None:
            return None, f"no flip value inferable for {g[:60]}"
        seeds = nxt
        nflip += 1
    return (seeds, scen, p, sd, nflip), None


plans = []          # (class_idx, base_idx, seeds, scen, path, nflip)
skipped = collections.Counter()
for ci, a in enumerate(classes):
    exprs = [a["expr"]] + [g for g, _o in a["conditioning"]]
    bases, total = candidates(exprs, K)
    a["_n_candidate_bases"] = total
    for bi, b in enumerate(bases):
        built, why = build(a, b)
        if built is None:
            skipped[why[:40]] += 1
            continue
        seeds, scen, p, sd, nflip = built
        plans.append((ci, bi, seeds, scen, p, nflip))
print(f"[plan] {len(plans)} probe plan(s) over {len(classes)} class(es); "
      f"skipped {sum(skipped.values())}", flush=True)

cache = A.ProbeCache(cfg, keep=False)
cache.planning = True
for ci, bi, seeds, scen, p, nflip in plans:
    cache.run(seeds, scen, "c27fals")
cache.planning = False
cache.execute()

results = collections.defaultdict(list)
for ci, bi, seeds, scen, p, nflip in plans:
    a = classes[ci]
    d = a["expr"]
    gates = [(g, side == "taken") for g, side in a["conditioning"]]
    sd = A.load_dump(p)
    r = cache.run(seeds, scen, "c27fals")
    if r is None:
        results[ci].append(("NOT-TESTABLE", os.path.basename(p), nflip,
                            "the probe produced no dump"))
        continue
    bad = None
    for e_ in [d] + [g for g, _o in gates]:
        why = A._reading_changed(sd, r, e_)
        if why:
            bad = why
            break
    if bad:
        results[ci].append(("NOT-COMPARABLE", os.path.basename(p), nflip, bad[:160]))
        continue
    unmet = [g for g, o in gates if o not in A.outcomes_of(r, g)]
    if unmet:
        results[ci].append(("NOT-TESTABLE", os.path.basename(p), nflip,
                            f"{len(unmet)} of {len(gates)} literal(s) unmet"))
        continue
    if A.recorded(r, d):
        results[ci].append(("FAIL", os.path.basename(p), nflip,
                            "REALISED C and RECORDED the member — §16g drop REFUTED"))
    else:
        results[ci].append(("PASS", os.path.basename(p), nflip,
                            "realised C, member left unevaluated"))
cache.close()

RANK = {"FAIL": 0, "PASS": 1, "NOT-COMPARABLE": 2, "NOT-TESTABLE": 3}
out, tally = [], collections.Counter()
for ci, a in enumerate(classes):
    rs = results.get(ci, [])
    verdict = min((r[0] for r in rs), key=lambda v: RANK[v]) if rs else "NOT-TESTABLE"
    tally[verdict] += 1
    out.append({"class": ci, "verdict": verdict, "expr": a["expr"],
                "conditioning": a["conditioning"], "A": a.get("matching_profiles"),
                "candidate_bases_in_corpus": a.get("_n_candidate_bases"),
                "bases_probed": len(rs),
                "per_base": [{"verdict": v, "base": b, "flips": f, "detail": det}
                             for v, b, f, det in rs]})
json.dump(out, open(OUT, "w"), indent=1)

print()
for o in out:
    pb = collections.Counter(x["verdict"] for x in o["per_base"])
    print(f"  [{o['class']:02d}] {o['verdict']:<14} bases {o['bases_probed']:>2}/"
          f"{o['candidate_bases_in_corpus']:<6} {dict(pb)}  {o['expr'][:70]}")
print()
print("C27-FALS RESULT: " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items())))
print(f"  per-base totals: {dict(collections.Counter(r[0] for rs in results.values() for r in rs))}")
print("C27-FALS-DONE")
