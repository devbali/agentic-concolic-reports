#!/usr/bin/env python3
"""P18 — WHAT REMAINS, classified by the CONSTRUCTION EVIDENCE (§80.10).

For every gap the last round drove and did not walk, join the first failing
literal to the P18 reach layer: the governing collection of that member ON THE
BASE THAT WAS CHOSEN, whether the cube itself demands that collection be in the
other state, whether the seed pinned it (plain or split), and whether the base
mints the api ordinal at all. That is the evidence the classification has to
carry — "never evaluated" alone is a symptom, not a class."""
import json, os, pickle, re, sys
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
idx = pickle.load(open(os.path.join(HERE, "_p18_index.pkl"), "rb"))
BSTAT = {}
for k, v in idx["bindstat"].items():
    a, b, c = k.split("\x00")
    BSTAT[(int(a), b, None if c == "None" else c)] = v
BINDS = [b[0] for b in idx["binds"]]
bypath = {os.path.basename(d[0]): i for i, d in enumerate(idx["dumps"])}
TAG = os.environ.get("P18_TAG", "P18D")
ex = json.load(open(os.path.join(HERE, f"_p15_explain_{TAG}.json")))["per_gap"]
man = {m["gap"]: m for m in json.load(open(os.path.join(HERE, "_p15_manifest.json")))
       if m["seed_set"] == "A"}
gaps = {g["id"]: g for g in json.load(open(os.path.join(HERE, "_p15_gaps.json")))}

_APIROW = re.compile(r"as_api_response_(\d+)_row_([a-z_]+)")
_ROWG = re.compile(r"(SYM_RESULT_ActiveRecord__(?:Relation|Associations__CollectionProxy)_"
                   r"(?:records|to_ary)[A-Za-z0-9_]*?)_row_")

def req(n, f, c):
    d = BSTAT.get((n, f, c))
    if not d: return "UNSEEN"
    reads = d.get((True, True), 0) + d.get((False, True), 0)
    if reads == 0: return "NEVER"
    if d.get((False, True), 0) == 0: return "NZ"
    if d.get((True, True), 0) == 0: return "Z"
    return "EITHER"

cls = Counter(); detail = Counter()
for gid, r in ex.items():
    if r["walked"]: continue
    fb, v = r["first_bad"], r["first_bad_v"]
    m = man.get(gid); g = gaps.get(gid)
    di = bypath.get(m["base"]) if m else None
    bnd = BINDS[di] if di is not None else {}
    clen = {}
    for lit in (g["node_constraint"] or "").split(" AND "):
        mm = re.search(r"\((SYM_LEN_[A-Za-z0-9_]+) != 0\)", lit)
        if mm: clen[mm.group(1)] = not lit.strip().startswith("Not(")
    a = _APIROW.search(fb or "")
    if a and v == "never_evaluated":
        n, f = int(a.group(1)), a.group(2)
        canon = bnd.get(n)
        if canon is None:
            cls["C1  base never makes that api call (ordinal absent on the base)"] += 1
        else:
            rq = req(n, f, canon)
            L = f"SYM_LEN_{canon}_rows"
            if rq == "NEVER":
                cls["C2  the base's binding for that ordinal NEVER reads that field"] += 1
                detail[f"C2 ord{n} {f} <- {canon[25:60]}"] += 1
            elif rq in ("NZ", "Z"):
                want = (rq == "NZ")
                if L in clen and clen[L] != want:
                    cls["C3  cube demands the governing collection in the OTHER state "
                        "(a SPLIT PIN was written; the run did not realise it)"] += 1
                    detail[f"C3 ord{n} {f} needs {rq} on {canon[25:60]}"] += 1
                else:
                    cls["C4  governor pinned to the required state, still not reached"] += 1
                    detail[f"C4 ord{n} {f} {rq} {canon[25:60]}"] += 1
            else:
                cls["C5  no measured requirement on that binding; reach not explained "
                    "by the length layer"] += 1
    elif v == "contradicted":
        mm = re.match(r"\((SYM_LEN_[A-Za-z0-9_]+) != 0\)", fb or "")
        if mm:
            cls["D1  a SPLIT length came out one-sided (only the non-empty ordinal "
                "was reached)"] += 1
            detail[f"D1 {mm.group(1)[33:75]}"] += 1
        else:
            cls[f"D2  contradicted, not a length gate: {fb[:60]}"] += 1
    elif v == "never_evaluated":
        rg = _ROWG.search(fb or "")
        if rg:
            L = f"SYM_LEN_{rg.group(1)}_rows"
            if L in clen and not clen[L]:
                cls["E1  a records-list row read whose OWN list the cube empties "
                    "(split written, not realised)"] += 1
            else:
                cls["E2  a records-list row read, list not emptied by the cube"] += 1
        else:
            cls[f"E3  other never-evaluated: {(fb or '')[:56]}"] += 1
print(f"NOT WALKED in round {TAG}: {sum(cls.values())}")
for k, c in cls.most_common():
    print(f"  {c:5d}  {k}")
print("\n  detail:")
for k, c in detail.most_common(16):
    print(f"     {c:5d}  {k}")
