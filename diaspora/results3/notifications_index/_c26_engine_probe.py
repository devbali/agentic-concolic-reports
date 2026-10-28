#!/usr/bin/env python3
"""C26 — the ENGINE's OWN §16g stage, replayed offline over the four witness
leaves, and cross-checked against `_c25_backward.py`'s four (C, d) findings.

Reads the bitsets `_c25_mincond.py` built over the C24R2 corpus (135 153
dumps, 21 exprs) and rebuilds `takes`/`evals`/`universe` at RUN granularity —
the engine uses PROFILES, and a profile exists iff some run has it, so the
`A > 0 / B = 0` partition (the only thing the inference reads) is identical
and only the A COUNTS differ.

Then, per witness leaf, it runs the SHIPPED
`coverage.wellfounded_drop_set(lits, probe, pinned, matched)` exactly as
step 6's emission side calls it:

  * `probe`  = the shipped `minimal_subconjunction` at W and the budget;
  * `pinned` = empty — these four leaves carry NO applied §16e drop (their
    own `conj` record has `F = []`) and NO applied §16f drop (every member of
    the recorded cube is still present), which is checked here rather than
    assumed;
  * `matched` = `prefix_match_mask(reduced) != 0`, the A(reduced leaf) > 0
    guard.

and compares the drop set, the conditioning sets and A against
`_c25_backward.json`.  DISAGREEMENT MEANS ONE OF THE TWO IS WRONG.

No src/ edit: the engine functions are IMPORTED.
"""
import json, os, pickle, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.coverage import (                        # noqa: E402
    minimal_subconjunction, prefix_match_mask, wellfounded_drop_set)

BITS = os.environ.get("BITS", os.path.join(HERE, "_c25_mincond_bits.pkl"))
CKPT = os.environ.get("CKPT", os.path.join(HERE, "_cov_c24_C24R2.ckpt.jsonl"))
BACK = os.environ.get("BACK", os.path.join(HERE, "_c25_backward.json"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_c26_engine_probe.json"))
WIDTHS = [int(x) for x in os.environ.get("WIDTHS", "3").split(",")]
BUDGETS = [int(x) for x in os.environ.get("BUDGETS", "20000,1000000000").split(",")]

st = pickle.load(open(BITS, "rb"))
EXPRS = st["exprs"]; N = st["n"]; TB = st["T"]; FB = st["F"]
EIDX = {e: i for i, e in enumerate(EXPRS)}
takes = {}
for e, j in EIDX.items():
    takes[(e, True)] = TB[j]
    takes[(e, False)] = FB[j]
evals = {e: TB[EIDX[e]] | FB[EIDX[e]] for e in EXPRS}
UNIV = (1 << N) - 1
print(f"bitsets: {len(EXPRS)} exprs over {N} runs", flush=True)

f = open(CKPT); f.readline()
leaves = []
for line in f:
    r = json.loads(line); v = r.get("v") or {}
    for combo in (v.get("combos") or []):
        leaves.append((r["k"], [(e, bool(o)) for e, o in combo],
                       v.get("conj") or [], v.get("subconj") or []))
f.close()
print(f"witness leaves: {len(leaves)}", flush=True)
back = {b["leaf"]: b for b in json.load(open(BACK))}

out = []
agree = disagree = 0
for li, (k, combo, conj, subconj) in enumerate(leaves):
    print(f"\n=== LEAF {li}  key {k}  width {len(combo)} ===", flush=True)
    members = [e for e, _o in combo]
    # PIN check, stated rather than assumed: no §16e drop was APPLIED on this
    # leaf's own gate prefix (every `conj` record whose prefix this cube
    # realises has F = []), and no §16f drop was applied to it (each recorded
    # (C, d) either names a member the cube still carries, i.e. it fired on a
    # DIFFERENT leaf of the same set, or does not apply here at all).
    lit_set = set(combo)
    applied_e = [rec for rec in conj
                 if rec[1] and set(tuple(x) for x in
                                   [(g, bool(o)) for g, o in rec[0]]) <= lit_set]
    applied_f = [rec for rec in subconj if rec[1] not in members
                 and set((g, bool(o)) for g, o in rec[0]) <= lit_set]
    print(f"  §16e drops applicable to THIS cube: {len(applied_e)};  "
          f"§16f: {len(applied_f)}  -> pin = "
          f"{'EMPTY' if not (applied_e or applied_f) else 'NON-EMPTY'}",
          flush=True)
    pin = set()
    for rec in applied_e:
        pin |= {g for g, _o in rec[0]}
    for rec in applied_f:
        pin |= {g for g, _o in rec[0]}

    rec_out = {"leaf": li, "key": k, "width": len(combo),
               "pin": sorted(pin), "by_width": {}}
    for W in WIDTHS:
        for bud in BUDGETS:
            hits = wellfounded_drop_set(
                tuple(combo),
                lambda p, m, _W=W, _b=bud: minimal_subconjunction(
                    p, m, takes, evals, UNIV, width=_W, budget=_b),
                pin,
                matched=lambda red: bool(prefix_match_mask(red, takes, UNIV)))
            drops = sorted(members.index(m) for m in hits)
            red = tuple(l for l in combo if l[0] not in hits)
            a_red = prefix_match_mask(red, takes, UNIV).bit_count()
            a_full = prefix_match_mask(tuple(combo), takes, UNIV).bit_count()
            key = f"W{W}_b{bud}"
            rec_out["by_width"][key] = {
                "drops": drops,
                "C": {str(members.index(m)):
                      {"C_pos": sorted(members.index(x) for x, _y in c),
                       "C": [[x, y] for x, y in c], "A": a}
                      for m, (c, a) in hits.items()},
                "A_full": a_full, "A_reduced": a_red,
                "reduced_width": len(red)}
            print(f"  {key}: kept {len(red)}  dropped {drops}  "
                  f"A(full)={a_full}  A(reduced)={a_red}", flush=True)
            for m, (c, a) in hits.items():
                print(f"      pos{members.index(m):2d} <- |C|={len(c)} A={a} "
                      f"from pos {sorted(members.index(x) for x, _y in c)}",
                      flush=True)
    # ---- CROSS-CHECK against _c25_backward.json (W=3, default budget) ----
    b = back.get(li)
    ref_drops = sorted(b["acyclic_drop"]) if b else []
    got = rec_out["by_width"][f"W{WIDTHS[0]}_b{BUDGETS[0]}"]
    ok = got["drops"] == ref_drops
    detail = []
    for p in ref_drops:
        rb = b["per_member"][str(p)]
        gb = got["C"].get(str(p))
        same = gb is not None and gb["C_pos"] == rb["C_pos"] and gb["A"] == rb["A"]
        ok = ok and same
        detail.append({"pos": p, "ref_C_pos": rb["C_pos"], "ref_A": rb["A"],
                       "eng_C_pos": gb and gb["C_pos"], "eng_A": gb and gb["A"],
                       "match": same})
    ok = ok and got["A_reduced"] == b["A_reduced"] and got["A_full"] == b["A_full"]
    rec_out["crosscheck"] = {"ref_drops": ref_drops, "eng_drops": got["drops"],
                             "ref_A_reduced": b["A_reduced"],
                             "eng_A_reduced": got["A_reduced"],
                             "per_member": detail, "agree": ok}
    print(f"  CROSS-CHECK vs _c25_backward.json: "
          f"{'AGREE' if ok else '*** DISAGREE ***'}  "
          f"drops ref={ref_drops} eng={got['drops']}  "
          f"A(reduced) ref={b['A_reduced']} eng={got['A_reduced']}", flush=True)
    for d in detail:
        print(f"      pos{d['pos']:2d} C_pos ref={d['ref_C_pos']} "
              f"eng={d['eng_C_pos']}  A ref={d['ref_A']} eng={d['eng_A']}  "
              f"{'ok' if d['match'] else 'MISMATCH'}", flush=True)
    agree += bool(ok); disagree += (not ok)
    out.append(rec_out)

json.dump(out, open(OUT, "w"), indent=1)
print(f"\nCROSS-CHECK TOTAL: agree {agree}, disagree {disagree}", flush=True)
print("C26-ENGINE-PROBE-DONE", flush=True)
