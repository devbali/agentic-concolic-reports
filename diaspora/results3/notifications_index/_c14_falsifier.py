#!/usr/bin/env python3
"""C14 — the §19.2 FALSIFIER count, computed on the corpus, per leaf group.

§19.2 proposes inferring foreclosure over the GATE CONJUNCTIONS a demand
already carries: if no run that satisfies a leaf's gate conjunction ever
EVALUATES a member decision, that member is foreclosed by the conjunction and
the checker should not demand it. That is a `src/` change, and this batch does
not make `src/` changes — but the OWNER needs the number either way, and the
number is a plain corpus fact:

  for each leaf group (demand set x gate prefix `pre`) and each member
  decision `m` of that group,
      A = runs whose walk AGREES with every literal of `pre`
      B = those of A that also EVALUATE `m`
  B > 0 is the FALSIFIER: the conjunction does NOT foreclose `m`, so the
  demand is a driving backlog, not an inference candidate.
  B = 0 over the whole corpus is the (defeasible) evidence FOR the inference.

Mask semantics, stated because they bound the claim: the index records
`em` = the decision was evaluated at least once in the run, `tm` = it came back
TAKEN at least once. A per-ROW decision can be BOTH ways in one run, so
"agrees with `pre`" is read as: for a True literal the run took it true at
least once; for a False literal the run took it false at least once
(`em & ~tm`). That is the same test the constructor's base scoring uses and it
is WEAKER than the checker's leaf-covering test — it can only OVERSTATE A and
B, so a B = 0 verdict is conservative in the direction that matters.

writes _c14_falsifier.json
"""
import json, os, pickle, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
GAPS  = os.environ.get("C14_GAPS",  os.path.join(HERE, "_c14_gaps.json"))
INDEX = os.environ.get("C14_INDEX", os.path.join(HERE, "_c14_index.pkl"))
OUT   = os.environ.get("C14_FALSIFIER", os.path.join(HERE, "_c14_falsifier.json"))

t0 = time.time()
idx = pickle.load(open(INDEX, "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
dumps = idx["dumps"]
gaps = json.load(open(GAPS))
UNIV = (1 << len(exprs)) - 1

# INVERTED BITSETS over the 116 570 RUNS (not over profiles): one big int per
# (expr, polarity) and per (expr, evaluated). A is then one AND-chain over the
# prefix literals and B one AND per member — exact run counts, seconds not hours.
N = len(dumps)
NB = (N + 7) // 8
TB = [bytearray(NB) for _ in exprs]
FB = [bytearray(NB) for _ in exprs]
EB = [bytearray(NB) for _ in exprs]
for i, (_p, _v, em, tm, _ns, _cm) in enumerate(dumps):
    by, bit = i >> 3, 1 << (i & 7)
    m = em
    while m:
        bb = m & -m; j = bb.bit_length() - 1; m ^= bb
        EB[j][by] |= bit
        if (tm >> j) & 1:
            TB[j][by] |= bit
        else:
            FB[j][by] |= bit
to_int = lambda ba: int.from_bytes(bytes(ba), "little")
TB = [to_int(x) for x in TB]; FB = [to_int(x) for x in FB]; EB = [to_int(x) for x in EB]
ALL = (1 << N) - 1
print(f"dumps {N}  exprs {len(exprs)}  inverted bitsets built ({time.time()-t0:.0f}s)",
      flush=True)

bygroup = defaultdict(list)
for g in gaps:
    bygroup[g["group"]].append(g)
print(f"leaf groups {len(bygroup)}", flush=True)

rows = {}
agg = Counter()
memstat = defaultdict(lambda: [0, 0])      # expr -> [groups_with_B0, groups]
for n, (gid, cubes) in enumerate(sorted(bygroup.items())):
    if n and n % 200 == 0:
        print(f"  {n}/{len(bygroup)}  {time.time()-t0:.0f}s", flush=True)
    pre = cubes[0]["pre"]
    mask = ALL
    unknown_pre = 0
    for e, o in pre.items():
        j = eidx.get(e)
        if j is None:
            unknown_pre += 1
            continue
        mask &= TB[j] if o else FB[j]
    A = mask.bit_count()
    members = sorted({e for c in cubes for e, _o in c["cube"]} - set(pre))
    per_member = {}
    for e in members:
        j = eidx.get(e)
        per_member[e] = (mask & EB[j]).bit_count() if j is not None else 0
    b0 = [e for e in members if per_member[e] == 0]
    rows[str(gid)] = {
        "set": cubes[0]["set"], "cubes": len(cubes),
        "checker_witness": bool(cubes[0].get("checker_witness")),
        "pre_width": len(pre), "members": len(members),
        "runs_matching_pre": A, "members_with_B0": len(b0),
        "member_B": per_member,
    }
    agg["groups"] += 1
    agg["cubes"] += len(cubes)
    if A == 0:
        agg["groups_no_run_matches_pre"] += 1
        agg["cubes_no_run_matches_pre"] += len(cubes)
    if b0:
        agg["groups_with_a_B0_member"] += 1
        agg["cubes_with_a_B0_member"] += len(cubes)
    if members and len(b0) == len(members):
        agg["groups_ALL_members_B0"] += 1
        agg["cubes_ALL_members_B0"] += len(cubes)
    if A > 0 and members and not b0:
        agg["groups_FULLY_FALSIFIED"] += 1
        agg["cubes_FULLY_FALSIFIED"] += len(cubes)
    for e in members:
        memstat[e][1] += 1
        if per_member[e] == 0:
            memstat[e][0] += 1

print("\n=== §19.2 FALSIFIER, over the whole corpus ===")
for k in ("groups", "cubes", "groups_no_run_matches_pre", "cubes_no_run_matches_pre",
          "groups_with_a_B0_member", "cubes_with_a_B0_member",
          "groups_ALL_members_B0", "cubes_ALL_members_B0",
          "groups_FULLY_FALSIFIED", "cubes_FULLY_FALSIFIED"):
    print(f"  {k:32s} {agg.get(k, 0)}")
print("\ntop members NEVER evaluated under their own gate conjunction "
      "(B=0 groups / groups):")
for e, (b0, tot) in sorted(memstat.items(), key=lambda kv: -kv[1][0])[:20]:
    print(f"   {b0:5d}/{tot:<5d}  {e[:100]}")
json.dump({"aggregate": dict(agg), "groups": rows}, open(OUT, "w"))
print(f"\nC14-FALSIFIER-DONE {OUT} ({os.path.getsize(OUT)/1e6:.1f} MB) "
      f"{time.time()-t0:.0f}s")
