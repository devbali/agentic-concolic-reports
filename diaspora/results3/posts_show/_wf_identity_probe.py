#!/usr/bin/env python3
"""Are the W-F pairs DEPENDENT, or are they ONE DECISION WITH TWO NAMES?

Coordinator question, 2026-09-11. W-F withdrew 507 of this endpoint's 1 787
tier-2 candidates on the inherited refutation "two not_found decisions share
the finder memo, so the pair produces a `FinderMethods.find_by` shape neither
single has". The owner's reading is that this describes an IDENTITY, not a
dependence: the mock memoizes the finder, the second call returns the SAME
object, the interceptor names results by CALL ORDINAL, and a memo hit issues no
SQL so the alias has no statement to key on. Flipping "both" would then be
flipping one value twice.

Four measurements per ordinal pair, over a stride sample of the FULL p5 corpus
(seed diversity is what matters here, so this does NOT use the pruned list):

  1. CO-EVALUATION and AGREEMENT — runs where both are evaluated, and of those,
     how many where the outcomes DIFFER. Zero disagreement over a large
     co-evaluated population is the identity signature.
  2. SEED CONTRADICTION — the decisive one. Each ordinal has its own seed key.
     If the second name is a memo hit, its OWN seed is ignored and its observed
     value follows the first's. Counted as (seeded, observed) pairs.
  3. SQL — does the ordinal's `symbolic_call` carry a statement note? A memo hit
     issues none, which is exactly why it has no statement to key an alias on.
  4. JOINT OUTCOMES — the 2x2 table actually observed. `found AND not-found`
     being empty is what makes the combination unsatisfiable under identity
     rather than merely unobserved.
"""
import json, os, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
LIST = os.environ.get("DUMP_LIST")
files = [l.strip() for l in open(LIST) if l.strip()]
files = [f if os.path.isabs(f) else os.path.join(HERE, f) for f in files]
print(f"scanning {len(files)} dumps", flush=True)

NF = re.compile(r"^\(SYM_RESULT_ActiveRecord__FinderMethods_find_by_(\d+)_not_found == True\)$")
SEEDKEY = "SYM_RESULT_ActiveRecord__FinderMethods_find_by_{}_not_found"

both = Counter(); differ = Counter(); joint = defaultdict(Counter)
seed_obs = defaultdict(Counter)
sql_present = Counter(); sql_absent = Counter(); seen_ord = Counter()
n = 0
for p in files:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    n += 1
    out = {}
    for ev in d.get("events") or ():
        if ev.get("type") == "path_condition":
            m = NF.match(str(ev.get("expr", "")))
            if m:
                out[int(m.group(1))] = bool(ev.get("taken"))
        elif ev.get("type") == "symbolic_call":
            rn = str(ev.get("result_name") or "")
            mm = re.search(r"FinderMethods_find_by_(\d+)$", rn)
            if mm:
                o = int(mm.group(1))
                seen_ord[o] += 1
                note = str(ev.get("note") or "")
                (sql_present if re.search(r"SELECT|WHERE", note, re.I) else sql_absent)[o] += 1
    seeds = d.get("concolic_seeds") or {}
    for o, v in out.items():
        sv = seeds.get(SEEDKEY.format(o), "<unseeded>")
        seed_obs[o][(sv, v)] += 1
    ks = sorted(out)
    for i, a in enumerate(ks):
        for b in ks[i + 1:]:
            both[(a, b)] += 1
            joint[(a, b)][(out[a], out[b])] += 1
            if out[a] != out[b]:
                differ[(a, b)] += 1
    del d

print(f"parsed {n} dumps\n")
print("=== 1+4. CO-EVALUATED not_found PAIRS: agreement and the 2x2 ===")
print(f"{'pair':<12}{'both_eval':>10}{'DIFFER':>9}   observed (a,b) cells")
ident, nonident = [], []
for pr in sorted(both, key=lambda k: -both[k]):
    cells = ", ".join(f"({int(x)},{int(y)}):{c}" for (x, y), c in sorted(joint[pr].items()))
    print(f"{str(pr):<12}{both[pr]:>10}{differ[pr]:>9}   {cells}")
    (ident if differ[pr] == 0 else nonident).append(pr)
print(f"\npairs that NEVER disagree (identity candidates): {len(ident)} of {len(both)}")
print(f"pairs that DO disagree (genuinely two decisions): {len(nonident)}")
if nonident:
    print("  disagreeing pairs:", nonident[:20])

print("\n=== 2. SEED CONTRADICTION per ordinal (is its own seed obeyed?) ===")
print(f"{'ord':>5}{'runs':>8}   (seeded -> observed) counts")
for o in sorted(seed_obs):
    tot = sum(seed_obs[o].values())
    cells = ", ".join(f"{s}->{int(v)}:{c}" for (s, v), c in
                      sorted(seed_obs[o].items(), key=lambda kv: -kv[1])[:6])
    contra = sum(c for (s, v), c in seed_obs[o].items()
                 if isinstance(s, bool) and s != v)
    print(f"{o:>5}{tot:>8}   {cells}    CONTRADICTED={contra}")

print("\n=== 3. SQL per ordinal (a memo hit issues none) ===")
print(f"{'ord':>5}{'calls':>8}{'with SQL':>10}{'no SQL':>9}")
for o in sorted(seen_ord):
    print(f"{o:>5}{seen_ord[o]:>8}{sql_present[o]:>10}{sql_absent[o]:>9}")

json.dump({"both": {str(k): v for k, v in both.items()},
           "differ": {str(k): v for k, v in differ.items()},
           "joint": {str(k): {str(kk): vv for kk, vv in v.items()} for k, v in joint.items()},
           "identity_candidates": [list(p) for p in ident],
           "disagreeing": [list(p) for p in nonident],
           "seed_obs": {str(o): {str(k): v for k, v in c.items()} for o, c in seed_obs.items()},
           "sql": {str(o): [seen_ord[o], sql_present[o], sql_absent[o]] for o in seen_ord}},
          open(os.path.join(HERE, "_wf_identity.json"), "w"), indent=1)
print("\nwrote _wf_identity.json")
