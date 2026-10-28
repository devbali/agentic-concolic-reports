#!/usr/bin/env python3
"""C16 — the residue, per key, WITH CONSTRUCTION EVIDENCE.

For every witness leaf a §16e coverage pass still reports, join:

  (a) was a seed BUILT for that exact cube and DRIVEN (the C16 batch)?
  (b) the classifier's per-cube verdict on those replays
      (REALISED / CONTRADICTED / UNEVALUATED / NOT-DRIVEN);
  (c) A over the FULL cube — how many runs of the corpus match every literal
      of the leaf at once (the falsifier's per-literal reading);
  (d) the leaf's §16e class, taken from the PASS's OWN `conj` records:
      A = 0 at the gate conjunction (the `unmatched` class, §13.3, demand
      STANDS) vs A > 0 (its gate conjunction IS walked; it is the full
      assignment that is not);
  (e) Rule T family membership — the nested row-length / identity decisions
      §27.13(4) named, which a seed at the head of the mock chain cannot
      control.

§28.4(a) FIX, kept: (c)/(d) are measured per (leaf, member) from the leaf's
OWN literals — never flattened to "B = 0 under SOME gate conjunction
anywhere", which is what over-counted §27.13's projection.

  usage: [C16_INDEX=..] [C16_GAPS=..] [C16_CLASSIFY=a.json,b.json]
         python3 -u _c16_residue.py <pass.ckpt.jsonl> [out.json]
"""
import json, os, pickle, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
CKPT = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "_c16_residue.json")
IDXP = os.environ.get("C16_INDEX", os.path.join(HERE, "_c16_index.pkl"))
GAPSP = os.environ.get("C16_GAPS", os.path.join(HERE, "_c16_gaps.json"))
CLS = [p for p in os.environ.get("C16_CLASSIFY", "").split(",") if p]
RULET = os.environ.get("C16_RULET", os.path.join(HERE, "_c16_ruleT_leaves.json"))

# ---- Rule T family (§27.13(4)): the decisions no seed at the head controls
_RT = re.compile(
    r"_row_target_photos_row_rows"
    r"|_row_target_mentions_container_photos_row_rows"
    r"|_row_target_mentions_container_commentable_photos_row_rows"
    r"|find_by_1_person_id == SYM_RESULT_ActiveRecord__FinderMethods_"
    r"devise_user_first_1_person_id")

# ---- corpus bitsets
idx = pickle.load(open(IDXP, "rb"))
exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}; dumps = idx["dumps"]
N = len(dumps); NB = (N + 7) // 8
TB = [bytearray(NB) for _ in exprs]; FB = [bytearray(NB) for _ in exprs]
EB = [bytearray(NB) for _ in exprs]
for i, (_p, _v, em, tm, _ns, _cm) in enumerate(dumps):
    by, b = i >> 3, 1 << (i & 7)
    m = em
    while m:
        bb = m & -m; j = bb.bit_length() - 1; m ^= bb
        EB[j][by] |= b
        (TB if (tm >> j) & 1 else FB)[j][by] |= b
ti = lambda x: int.from_bytes(bytes(x), "little")
TB = [ti(x) for x in TB]; FB = [ti(x) for x in FB]; EB = [ti(x) for x in EB]
ALL = (1 << N) - 1
print(f"index: {N} dumps, {len(exprs)} expressions", flush=True)

# ---- the batch, and what the classifier said about it
gaps = json.load(open(GAPSP)) if os.path.exists(GAPSP) else []
bycube = {}
for g in gaps:
    bycube.setdefault(tuple(sorted((e, bool(o)) for e, o in g["cube"])), []).append(g)
verdict = {}
for p in CLS:
    for gid, v in json.load(open(p))["per_gap"].items():
        verdict.setdefault(gid, []).append(v)
print(f"batch cubes {len(gaps)}   classified cubes {len(verdict)}", flush=True)

# ---- the pass's residue
rows = []
f = open(CKPT); json.loads(f.readline())
for line in f:
    r = json.loads(line); v = r.get("v") or {}
    combos = v.get("combos") or []
    if not combos:
        continue
    conj = v.get("conj") or []
    a0_gate = any(c[2] == 0 for c in conj)
    conj_fired = [c for c in conj if c[2] > 0 and c[1]]
    for c in combos:
        cube = sorted({(e, bool(o)) for e, o in c})
        key = tuple(cube)
        # A over the FULL cube
        m = ALL; unk = 0
        for e, o in cube:
            j = eidx.get(e)
            if j is None:
                unk += 1; continue
            m &= TB[j] if o else FB[j]
        # per-member: is it EVALUATED by any run matching the leaf's OTHER
        # literals? (the falsifier's shape, per THIS leaf, never flattened)
        mem = []
        for e, o in cube:
            mm = ALL; u2 = 0
            for e2, o2 in cube:
                if e2 == e:
                    continue
                j2 = eidx.get(e2)
                if j2 is None:
                    u2 += 1; continue
                mm &= TB[j2] if o2 else FB[j2]
            j = eidx.get(e)
            mem.append({"expr": e, "outcome": o,
                        "A_others": mm.bit_count(),
                        "evaluated_under_others":
                            (mm & EB[j]).bit_count() if j is not None else -1,
                        "taken_that_way_under_others":
                            (mm & (TB[j] if o else FB[j])).bit_count()
                            if j is not None else -1,
                        "rule_T": bool(_RT.search(e))})
        built = bycube.get(key, [])
        vs = [x for g in built for x in verdict.get(g["id"], [])]
        rows.append({
            "set": r["k"], "width": len(cube),
            "A_whole_leaf": m.bit_count(), "expr_not_in_index": unk,
            "A0_at_gate_conjunction": a0_gate,
            "conj_foreclosures_on_this_set": len(conj_fired),
            "in_C16_batch": bool(built),
            "batch_ids": [g["id"] for g in built],
            "batch_class": sorted({("A=0" if g.get("unmatched") else
                                    "coarsened" if g.get("cf") else
                                    "witness" if g.get("checker_witness") else
                                    "plain") for g in built}),
            "driven_verdicts": sorted(set(vs)),
            "verdict": ("REALISED" if "REALISED" in vs else
                        "CONTRADICTED" if "CONTRADICTED" in vs else
                        "UNEVALUATED" if "UNEVALUATED" in vs else
                        "NOT-DRIVEN" if vs else "NOT-IN-BATCH"),
            "rule_T_members": sum(1 for x in mem if x["rule_T"]),
            "members_never_evaluated_under_the_others":
                sum(1 for x in mem if x["evaluated_under_others"] == 0),
            "members_A_others_zero": sum(1 for x in mem if x["A_others"] == 0),
            "keys": mem,
        })

agg = Counter()
for x in rows:
    agg[x["verdict"]] += 1
    agg["A_whole=0"] += (x["A_whole_leaf"] == 0)
    agg["A0_at_gate_conjunction"] += x["A0_at_gate_conjunction"]
    agg["has_rule_T_member"] += (x["rule_T_members"] > 0)
    agg["in_batch"] += x["in_C16_batch"]
sets_gapped = len({x["set"] for x in rows})
print(f"\nwitness leaves {len(rows)}   over {sets_gapped} gap-sets")
for k, n in agg.most_common():
    print(f"   {n:5d}  {k}")
by_set = defaultdict(set)
for x in rows:
    by_set[x["verdict"]].add(x["set"])
print("\n  gap-SETS by verdict of their witness leaf:")
for k, s in sorted(by_set.items(), key=lambda kv: -len(kv[1])):
    print(f"   {len(s):5d}  {k}")
json.dump({"checkpoint": CKPT, "aggregate": dict(agg),
           "gap_sets": sets_gapped, "leaves": rows}, open(OUT, "w"), indent=1)
print(f"\nC16-RESIDUE-DONE {OUT}")
