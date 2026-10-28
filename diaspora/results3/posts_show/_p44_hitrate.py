#!/usr/bin/env python3
"""P44 — THE TARGETING HIT RATE on cubes the corpus PROVABLY CONTAINS.

Joins the control gaps (each carrying `ctrl_dump`, a run on disk that realises
the cube), the constructor's manifest, and `_p15_explain.py`'s per-gap verdict.
Ground truth is 100 %; every miss is classified.

  usage: python3 _p44_hitrate.py <ctrl_gaps.json> <manifest.json> <explain.json>
"""
import json, os, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
_FAM = [(r"as_api_response_\d+_row_guid", "guid"),
        (r"^\(SYM_LEN_.*_rows != 0\)$", "length gate (rows)"),
        (r"^\(SYM_LEN_.*_ids != 0\)$", "length gate (ids)"),
        (r"_text_empty == True", "text (empty)"),
        (r"_text_has_mention == True", "text (has_mention)"),
        (r"find_by_\d+_not_found", "find_by not_found"),
        (r"findpublic_.*_not_found", "findpublic not_found"),
        (r"findpublic_.*_public == True", "public gate"),
        (r"_not_found == True", "evilq not_found"),
        (r"Anonymous_process_\d+ == ''", "text (rendered)"),
        (r"assoc_profile_nsfw", "nsfw gate"),
        (r"Length\(SYM_PARAM_id\)", "param id length"),
        (r"_row_status_message_guid !=", "guid self-compare")]
def family(e):
    for pat, name in _FAM:
        if re.search(pat, e or ""):
            return name
    return "other"

ctrl = {c["id"]: c for c in json.load(open(sys.argv[1]))}
man = {m["gap"]: m for m in json.load(open(sys.argv[2]))}
ex = json.load(open(sys.argv[3]))
pg = ex["per_gap"]

N = len(ctrl)
driven = len(pg)
walked = sum(1 for r in pg.values() if r["walked"])
print("=" * 74)
print(f"P44 TARGETING HIT RATE — cubes the corpus PROVABLY CONTAINS")
print("=" * 74)
print(f"  control cubes (ground truth: each is realised by a named dump) : {N}")
print(f"  seeds built by the constructor                                 : {len(man)}")
print(f"  gaps with at least one driven dump                             : {driven}")
print(f"  gaps NOT driven (seed produced no dump)                        : {N - driven}")
print(f"  HIT (driven run realises every cube literal)                   : {walked}")
print(f"  HIT RATE                                                       : "
      f"{100.0*walked/max(N,1):.1f} %")
print()
C = Counter(); byfam = Counter(); base_is_witness = Counter()
rows = []
for gid, c in ctrl.items():
    r = pg.get(gid)
    m = man.get(gid)
    bw = (m and m["base"] == c["ctrl_dump"])
    if r is None:
        cls = "NO DUMP (seed never driven / lost)"
    elif r["walked"]:
        cls = "HIT"
    elif r["c"]:
        cls = f"MISS: literal CONTRADICTED"
    else:
        cls = f"MISS: literal NEVER EVALUATED"
    C[cls] += 1
    base_is_witness[(cls, "base==witness" if bw else "base!=witness")] += 1
    if r and not r["walked"]:
        byfam[(r["first_bad_v"], family(r["first_bad"]))] += 1
    rows.append({"id": gid, "cls": cls, "base": m and m["base"],
                 "witness": c["ctrl_dump"], "base_is_witness": bool(bw),
                 "width": len(c["node_constraint"].split(" AND ")),
                 "set": c["set"], "variant": c["ctrl_variant"],
                 "ctrl_candidates": c["ctrl_candidates"],
                 "admissibility": m and m["admissibility"],
                 "values_written": m and m["values_written"],
                 "first_bad": r and r["first_bad"], "first_bad_v": r and r["first_bad_v"],
                 "h": r and r["h"], "c": r and r["c"], "n": r and r["n"]})
print("VERDICT CLASSES")
for k, n in C.most_common():
    print(f"   {n:6d}  {100.0*n/N:5.1f} %  {k}")
print()
print("FIRST FAILING LITERAL, by verdict x family")
for (v, f), n in byfam.most_common(20):
    print(f"   {n:6d}  {v:16s} {f}")
print()
print("WAS THE CONSTRUCTOR'S BASE THE WITNESS DUMP?")
for k, n in sorted(base_is_witness.items()):
    print(f"   {n:6d}  {k[0]:34s} {k[1]}")
print()
w = Counter(); wt = Counter()
for r in rows:
    wt[r["width"]] += 1
    if r["cls"] == "HIT":
        w[r["width"]] += 1
print("HIT RATE BY CUBE WIDTH")
for k in sorted(wt):
    print(f"   width {k:3d}   {w[k]:4d}/{wt[k]:<4d}  {100.0*w[k]/wt[k]:5.1f} %")
out = os.environ.get("P44_ROWS", os.path.join(HERE, "_p44_hitrate_rows.json"))
json.dump({"n": N, "driven": driven, "walked": walked, "classes": dict(C),
           "rows": rows}, open(out, "w"), indent=1)
print(f"\nrows -> {os.path.basename(out)}")
print("P44-HITRATE-DONE")
