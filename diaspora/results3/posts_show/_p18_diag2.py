#!/usr/bin/env python3
"""P18 — the diagnosis distribution asked for: per witness, which ROW-INDEXED
members it carries, which LIST LENGTH governs each, what the corpus/base walks
and what is needed. Built on the FULL 36 677-profile index (`_p18_index.pkl`),
not a sample."""
import json, os, pickle, re, sys
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
idx = pickle.load(open(os.path.join(HERE, "_p18_index.pkl"), "rb"))
BSTAT = {}
for k, v in idx["bindstat"].items():
    a, b, c = k.split("\x00")
    BSTAT[(int(a), b, None if c == "None" else c)] = v
BINDS = [b[0] for b in idx["binds"]]
DOM = idx["domain"]
gaps = json.load(open(os.path.join(HERE, "_p15_gaps.json")))
man = {m["gap"]: m for m in json.load(open(os.path.join(HERE, "_p15_manifest.json")))
       if m["seed_set"] == "A"}
bypath = {os.path.basename(d[0]): i for i, d in enumerate(idx["dumps"])}

_APIROW = re.compile(r"SYM_RESULT_ActsAsApi__Collection_as_api_response_(\d+)_row_([a-z_]+)")
_ROW = re.compile(r"(SYM_RESULT_ActiveRecord__(?:Relation|Associations__CollectionProxy)_"
                  r"(?:records|to_ary)[A-Za-z0-9_]*?)_row_([a-z_]+)")

def req(n, f, c):
    d = BSTAT.get((n, f, c))
    if not d: return "UNSEEN"
    reads = d.get((True, True), 0) + d.get((False, True), 0)
    if reads == 0: return "NEVER"
    if d.get((False, True), 0) == 0: return "NZ"
    if d.get((True, True), 0) == 0: return "Z"
    return "EITHER"

print("== 1. ROW-INDEXED MEMBERS ACROSS THE 340 P17 WITNESSES")
famc = Counter(); ordc = Counter(); rowc = Counter()
for g in gaps:
    nc = g["node_constraint"]
    for m in set(_APIROW.findall(nc)):
        famc[f"api_{m[1]}"] += 1; ordc[(int(m[0]), m[1])] += 1
    for m in set(_ROW.findall(nc)):
        famc[f"row_{m[1]}"] += 1
        rowc[m[0][len('SYM_RESULT_ActiveRecord__'):]] += 1
for k, c in famc.most_common(): print(f"   {c:6d}  {k}")
print("\n   api (ordinal, field) member slots:")
for k, c in sorted(ordc.items()): print(f"      ord {k[0]}  {k[1]:<18} {c}")
print("\n   records-list row reads, by list:")
for k, c in rowc.most_common(10): print(f"      {c:5d}  {k[:64]}")

print("\n== 2. THE GOVERNOR OF EACH api ROW READ, AND WHAT IT MUST BE")
print("   (measured over 36 677 profiles; NZ = the collection must be non-empty)")
seen = set()
for (n, f, c), d in sorted(BSTAT.items(), key=lambda x: (x[0][0], x[0][1], str(x[0][2]))):
    reads = d.get((True, True), 0) + d.get((False, True), 0)
    if reads == 0 or c is None: continue
    print(f"   ord {n} {f:<18} {c[len('SYM_RESULT_ActiveRecord__'):][:46]:<48} -> {req(n,f,c)}")

print("\n== 3. PER WITNESS: what the CHOSEN BASE walks vs what the cube needs")
tab = Counter(); ordneed = Counter()
for g in gaps:
    m = man.get(g["id"])
    di = bypath.get(m["base"]) if m else None
    bnd = BINDS[di] if di is not None else {}
    for (sn, sf) in set(_APIROW.findall(g["node_constraint"])):
        n = int(sn); canon = bnd.get(n)
        r = req(n, sf, canon) if canon else "NO-CALL"
        tab[(n, sf, r)] += 1
        ordneed[r] += 1
for k in sorted(tab): print(f"   ord {k[0]} {k[1]:<18} base-binding requirement {k[2]:<8} {tab[k]}")
print("\n   summary over all api member slots of all 340 witnesses:")
for k, c in ordneed.most_common(): print(f"      {c:6d}  {k}")

print("\n== 4. NEEDED LENGTH vs WALKED LENGTH")
print("   The needed length is >= 1 for a guid read and == 0 for a has_mention /")
print("   text_empty read at ordinals 1 and 4; the corpus's own distribution of")
print("   each governing length (how many profiles walk each value):")
for L in sorted({f"SYM_LEN_{c}_rows" for (_n, _f, c) in BSTAT if c}):
    d = DOM.get(L) or {}
    tot = sum(d.values()); nz = sum(v for k, v in d.items() if k not in ("0", "None"))
    print(f"   {L[len('SYM_LEN_SYM_RESULT_ActiveRecord__'):][:56]:<58} "
          f"profiles={tot:6d} >=1:{nz:6d}  {dict(sorted(d.items())[:6])}")
print("P18-DIAG2-DONE")
