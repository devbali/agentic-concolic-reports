#!/usr/bin/env python3
"""C18 — score the ACTIVE FALSIFICATION drive of RE-MINT-IDENTITY.

For every C18F replay: was the seeded upstream length actually REALISED
(the realised-value rule: seeding is not realising), and did the re-minted
association length come back EQUAL to it?

  usage: [TAG=C18F] python3 -u _c18_fals_classify.py [out.json]
"""
import glob, json, os, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
import coverage_report as CR                        # noqa: E402
import coverage_assumptions as CA                   # noqa: E402

TAG = os.environ.get("TAG", "C18F")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_c18f_classify.json")
REMINT = re.compile(r"^preloaded association #([a-z_]+):")
BIND = re.compile(r"\$\$\(([A-Za-z0-9_]+)\)")
CP = "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_"
TABLE = {"followed_tags": "tags"}

man = {m["gap"]: m for m in json.load(open(os.path.join(HERE, "_c18f_manifest.json")))}
files = sorted(glob.glob(os.path.join(HERE, f"dump_*_{TAG}*.json")))
print(f"manifest {len(man)} seeds; replay dumps {len(files)}", flush=True)

eq = Counter(); ne = Counter(); realised = Counter(); byassoc = Counter()
upvals = defaultdict(Counter); runs = 0; errs = Counter(); nopair = 0
diffs = []
for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    gid = (d.get("concolic_seeds") or {}).get("__c13gap__")
    m = man.get(gid)
    if m is None:
        continue
    runs += 1
    errs[(d.get("error") or {}).get("type") or "-"] += 1
    CR.canonicalize_ordinals(d, CA.ALIASES)
    svs = {sv.get("name"): sv for sv in (d.get("symbolic_vars") or ()) if sv.get("name")}
    cps = [(n, sv) for n, sv in svs.items() if n.startswith(CP)]
    found = 0
    for n, sv in svs.items():
        mm = REMINT.match(sv.get("note") or "")
        if not (mm and n.startswith("len(")):
            continue
        assoc = mm.group(1); base = n[4:-1]; tail = f"_{assoc}_row_rows"
        if not base.endswith(tail):
            continue
        owner = base[:-len(tail)]; tbl = TABLE.get(assoc, assoc)
        for n2, sv2 in cps:
            if not n2.startswith(CP + tbl + "_"):
                continue
            if not any(b.startswith(owner) for b in BIND.findall(sv2.get("note") or "")):
                continue
            found += 1
            k = (base, n2[4:-1])
            upvals[assoc][sv2.get("value")] += 1
            realised[f"seed={m['value']} -> upstream={sv2.get('value')}"] += 1
            byassoc[assoc] += 1
            if sv.get("value") == sv2.get("value"):
                eq[k] += 1
            else:
                ne[k] += 1
                if len(diffs) < 10:
                    diffs.append({"dump": os.path.basename(fp), "seed": m["value"],
                                  "remint": base, "remint_val": sv.get("value"),
                                  "upstream": n2[4:-1], "up_val": sv2.get("value")})
    if not found:
        nopair += 1

E, N = sum(eq.values()), sum(ne.values())
print(f"\nreplays scored {runs}   errors {dict(errs)}")
print(f"runs with no (re-mint, upstream) pair minted: {nopair}")
print(f"paired observations: {E+N}   EQUAL {E}   DIFFERENT {N}")
print(f"distinct canonical pairs exercised: {len(set(eq) | set(ne))}")
print("\nupstream length values REALISED, per association family "
      "(the realised-value rule: seeding is not realising):")
for a in sorted(upvals):
    print(f"   {a:22s} {dict(sorted(upvals[a].items()))}")
print("\nseed -> realised upstream value:")
for k in sorted(realised):
    print(f"   {realised[k]:6d}  {k}")
if diffs:
    print("\nDISAGREEMENTS (the falsifier FIRING):")
    for x in diffs:
        print("   ", x)
verdict = "PASS" if (N == 0 and E >= 200) else "FAIL" if N else "INSUFFICIENT"
print(f"\nC18-FALSIFICATION {verdict}  (equal {E}, different {N}, "
      f"runs {runs})")
json.dump({"tag": TAG, "runs": runs, "errors": dict(errs), "equal": E,
           "different": N, "pairs": len(set(eq) | set(ne)),
           "by_assoc": dict(byassoc),
           "upstream_values": {a: dict(upvals[a]) for a in upvals},
           "seed_to_realised": dict(realised),
           "disagreements": diffs, "verdict": verdict}, open(OUT, "w"), indent=1)
print(f"C18-FALS-CLASSIFY-DONE {OUT}")
