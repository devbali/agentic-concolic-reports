#!/usr/bin/env python3
"""Are tier 2's 1 733 pairs NON-FORECLOSING? (coordinator, 2026-09-11)

Removal-type dependence IS foreclosure, and §16b already handles it by never
demanding the combination — the pruned tree has no cube with both members. A
declared independence over such a pair is REDUNDANT with the foreclosure
relation: it costs nothing and confuses the record. Tier 2's claim is only about
pairs that are CO-EVALUATED and NON-FORECLOSING, where the only dependence that
can move the policy is additive/substitutive.

This consults the engine's OWN inferred relation — the same `infer_foreclosures`
call the pass and the census make — and drops any pair where either member
forecloses the other on any outcome.
"""
import json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
import _exact_enum_emit as EE                                  # noqa: E402
from coverage_assumptions import build as build_assumptions    # noqa: E402

t0 = time.time()
runs = EE.load_runs()
A = build_assumptions(runs)
U = EE.build_universe(runs, A, int(os.environ.get("MAX_CLIQUES", "16384")))
assert U is not None
print(f"universe built in {time.time()-t0:.0f}s", flush=True)

by_gate, bit = U["by_gate"], U["bit"]
# (gate, outcome) -> set of expressions it forecloses
fore = {}
for g, lst in by_gate.items():
    for o, mask in lst:
        s = {e for e in bit if (mask >> bit[e]) & 1}
        if s:
            fore[(g, o)] = s
print(f"foreclosure relation: {len(fore)} (gate,outcome) entries over "
      f"{len({g for g, _ in fore})} gates", flush=True)

cand = [tuple(x) for x in json.load(open(os.path.join(HERE, "_tier2_after_wf.json")))["kept"]]
keep, drop = [], []
for a, b, ka, kb in cand:
    af = any(b in fore.get((a, o), ()) for o in (True, False))
    bf = any(a in fore.get((b, o), ()) for o in (True, False))
    (drop if (af or bf) else keep).append((a, b, ka, kb, af, bf))

print(f"\ntier 2 candidates            : {len(cand)}")
print(f"FORECLOSING (drop, redundant): {len(drop)}")
print(f"NON-FORECLOSING (tier 2)     : {len(keep)}")
from collections import Counter
import re
FAM = [(re.compile(r"_[0-9a-f]{8}(?![0-9a-f])"), "_<hash>"), (re.compile(r"_[0-9]+(?![0-9])"), "_<n>")]
def fam(k):
    for rx, r in FAM:
        k = rx.sub(r, k)
    return k
dc = Counter(tuple(sorted((fam(x[2]), fam(x[3])))) for x in drop)
kc = Counter(tuple(sorted((fam(x[2]), fam(x[3])))) for x in keep)
print(f"\nclasses with a dropped pair: {len(dc)};  classes still populated: {len(kc)}")
for (fa, fb), n in dc.most_common(10):
    print(f"   DROP {n:5d}  {fa.split('__')[-1][:44]}  x  {fb.split('__')[-1][:44]}")
json.dump({"kept": [list(x[:4]) for x in keep],
           "dropped": [list(x[:4]) for x in drop],
           "n_cand": len(cand), "n_keep": len(keep), "n_drop": len(drop),
           "keep_classes": [[list(k), v] for k, v in kc.most_common()],
           "drop_classes": [[list(k), v] for k, v in dc.most_common()]},
          open(os.path.join(HERE, "_forecl_check.json"), "w"), indent=1)
print(f"\nwrote _forecl_check.json ({time.time()-t0:.0f}s)")
