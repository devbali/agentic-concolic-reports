#!/usr/bin/env python3
"""P44 — IS THE MISS A CONSTRUCTOR FAILURE OR SELF-FORECLOSING DEMAND?

Every miss on the real residue is `never_evaluated`. For each one, ask what the
CORPUS says about reaching that member, and whether the cube ITSELF demands a
condition the corpus says forecloses it:

  A  SELF-FORECLOSED   the cube demands (f=o) and, over >= MIN_RUNS runs with
                       f=o, the member was NEVER evaluated. No seed can help;
                       the demand is unreachable in this program-as-mocked.
  B  REACHABLE, PIN KNOWN   a condition exists, the cube does not contradict it,
                       and the seed did not honour it -> a constructor fix.
  C  REACHABLE, NO PIN KNOWN   the corpus carries no condition at all ->
                       the reach layer cannot express it; needs a new measure.

  usage: _p44_missreason.py <gaps.json> <explain.json>
"""
import json, os, pickle, sys
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
IDX = os.environ.get("P44_INDEX", os.path.join(HERE, "_p31_index_P35C.pkl"))
MIN = int(os.environ.get("P44_MIN_RUNS", "200"))

idx = pickle.load(open(IDX, "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
LENS = idx["lens"]; LIDX = {L: i for i, L in enumerate(LENS)}
dumps = idx["dumps"]
EM = [d[2] for d in dumps]; TM = [d[3] for d in dumps]; DFM = [d[8] for d in dumps]
DL0 = [d[6] for d in dumps]; DL1 = [d[7] for d in dumps]
N = len(dumps)

# reach conditions, ONE-SIDED only, over decisions AND lengths, recomputed here
# so the table and the verdict cannot drift apart.
ev = [0]*len(exprs)
for i in range(N):
    em = EM[i]
    for j in range(len(exprs)):
        if (em >> j) & 1:
            ev[j] += 1
COND = defaultdict(list)          # expr -> [(kind, name, outcome)] that FORBID it
for e in range(len(exprs)):
    if ev[e] < MIN:
        continue
    for f in range(len(exprs)):
        if f == e:
            continue
        zero = []
        for o, M in ((0, DFM), (1, TM)):
            sel = [i for i in range(N) if (M[i] >> f) & 1]
            if len(sel) < MIN:
                continue
            if not any((EM[i] >> e) & 1 for i in sel):
                zero.append(o)
        if len(zero) == 1:                       # one-sided only
            COND[exprs[e]].append(("expr", exprs[f], bool(zero[0])))
    for j in range(len(LENS)):
        zero = []
        for o, M in ((0, DL0), (1, DL1)):
            sel = [i for i in range(N) if (M[i] >> j) & 1]
            if len(sel) < MIN:
                continue
            if not any((EM[i] >> e) & 1 for i in sel):
                zero.append(o)
        if len(zero) == 1:
            COND[exprs[e]].append(("len", LENS[j], bool(zero[0])))
print(f"reach conditions (one-sided, MIN_RUNS={MIN}): "
      f"{sum(len(v) for v in COND.values())} over {len(COND)} expressions",
      flush=True)

gaps = {g["id"]: g for g in json.load(open(sys.argv[1]))}
ex = json.load(open(sys.argv[2]))["per_gap"]

def demands(nc):
    d = {}
    for part in (nc or "").split(" AND "):
        s = part.strip(); pol = True
        while s.startswith("Not(") and s.endswith(")"):
            s = s[4:-1].strip(); pol = not pol
        d[s] = pol
    return d

# CONJUNCTION PINS (2026-09-17, _p44_reachnec_conj.py). Only single-condition
# reach necessity was in COND above; these 3 pairs were found by testing
# genuine 2-way conjunctions over the SAME frozen index (neither atom alone
# forecloses the target, the pair together does, n>=200). Scoped to the 2
# targets they were measured against -- do NOT generalise to other targets
# without re-running the conjunction scan for them. A cube matching BOTH
# atoms at the co-foreclosing polarity is A2 (self-foreclosed via a
# conjunction) -- kept PROVISIONAL, never auto-declared unreachable, per
# standing discipline (would need the §16b/independence falsifier to become
# more than provisional). A cube mentioning only one conjunct is B2 -- a new
# constructor pin candidate, same status as a single-condition B.
CONJ_TARGETS = {
    "(assoc_status_message_text_has_mention == True)",
    "(assoc_status_message_text_empty == True)",
}
CONJ_PAIRS = [
    (("len", "SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_photos_9930492e_rows", False),
     ("expr", "(SYM_RESULT_ActiveRecord__Relation_evilq_like_public_1_not_found == True)", True)),
    (("len", "SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_photos_9930492e_rows", False),
     ("expr", "(SYM_RESULT_ActiveRecord__Relation_evilq_reshare_public_1_not_found == True)", True)),
    (("len", "SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_photos_e035b5b3_rows", False),
     ("expr", "(SYM_RESULT_ActiveRecord__Relation_findpublic_reshare_1_public == True)", False)),
]

def _conj_var(kind, name):
    return f"({name} != 0)" if kind == "len" else name

def conj_check(tgt, dem):
    """-> 'A2', 'B2', or None"""
    if tgt not in CONJ_TARGETS:
        return None
    full = False; partial = False
    for (k1, n1, o1), (k2, n2, o2) in CONJ_PAIRS:
        v1, v2 = _conj_var(k1, n1), _conj_var(k2, n2)
        if dem.get(v1) == o1 and dem.get(v2) == o2:
            full = True
        elif (v1 in dem) or (v2 in dem):
            partial = True
    return "A2" if full else ("B2" if partial else None)

V = Counter(); BYFAM = Counter()
for gid, r in ex.items():
    if r["walked"]:
        continue
    tgt = r["first_bad"]
    dem = demands(gaps[gid]["node_constraint"])
    cs = COND.get(tgt) or []
    hit = None
    for kind, name, out in cs:
        if kind == "expr":
            if dem.get(name) == out:
                hit = (kind, name, out); break
        else:
            lexpr = f"({name} != 0)"
            if dem.get(lexpr) is not None and dem[lexpr] == out:
                hit = (kind, name, out); break
    # RELEVANCE FILTER (2026-09-17): a condition only supports "B" if its own
    # variable is part of THIS cube's demand set. At small corpus/index sizes
    # almost every `cs` was empty, so "cs non-empty" and "cs relevant" were
    # nearly the same test. At UNION2 scale (113/120 exprs carry SOME global
    # condition) `cs` is almost never empty, so the old `elif cs:` collapsed
    # B to ~100% regardless of whether the condition had anything to do with
    # the cube being tested (verified: sampled B-classified misses whose
    # listed conditions' variables did not appear in the cube's own literals
    # at all). Relevance is required for a real B/A verdict; without it, no
    # known condition actually BEARS on this cube, so it is C by the
    # classifier's own definition ("the reach layer cannot express it" ==
    # cannot express anything applicable to what this cube demands).
    def cond_var(kind, name):
        return f"({name} != 0)" if kind == "len" else name
    relevant = [c for c in cs if cond_var(c[0], c[1]) in dem]
    if hit:
        V["A SELF-FORECLOSED (the cube demands a condition that forbids the member)"] += 1
        BYFAM[(tgt[:70], f"{hit[1][:56]}={hit[2]}")] += 1
    elif relevant:
        V["B reachable, a RELEVANT condition is known and not contradicted"] += 1
    else:
        cj = conj_check(tgt, dem)
        if cj == "A2":
            V["A2-CONJ-PROVISIONAL (matches a 2-way conjunction foreclosure, NOT falsifier-tested)"] += 1
        elif cj == "B2":
            V["B2-CONJ (2-way conjunction pin candidate, mentions one conjunct)"] += 1
        else:
            V["C no condition known THAT BEARS ON THIS CUBE -- reach layer cannot express it"] += 1
tot = sum(V.values())
print(f"\nMISSES CLASSIFIED ({tot})")
for k, n in V.most_common():
    print(f"   {n:6d}  {100.0*n/max(tot,1):5.1f} %  {k}")
print("\nTOP SELF-FORECLOSING PAIRS")
for k, n in BYFAM.most_common(12):
    print(f"   {n:5d}  {k[0]}\n            forbidden by  {k[1]}")
print("P44-MISSREASON-DONE")
