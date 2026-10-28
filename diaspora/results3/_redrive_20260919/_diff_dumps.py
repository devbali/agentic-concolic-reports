#!/usr/bin/env python3
"""Diff two dump sets produced from the SAME seeds under different RAILS_ENVs.

Checks the branching-safety assumption directly:
  * same set of path-condition signatures
  * same per-dump PC count
and then reports exactly how the recorded SQL notes differ.

Usage: _diff_dumps.py <dirA> <dirB>
"""
import json
import os
import sys
from collections import Counter


def pcs_of(d):
    out = []
    for ev in d.get("events", []):
        if ev.get("kind") == "path_condition" or "taken" in ev:
            out.append((str(ev.get("expr")), ev.get("taken")))
    return out


def notes_of(d):
    ns = []
    for sr in d.get("symbolic_results", []) or []:
        n = sr.get("note")
        if n:
            ns.append(n)
    for ev in d.get("events", []) or []:
        n = ev.get("note")
        if n:
            ns.append(n)
    return ns


def load(dirpath):
    out = {}
    for f in sorted(os.listdir(dirpath)):
        if not (f.startswith("dump_") and f.endswith(".json")):
            continue
        d = json.load(open(os.path.join(dirpath, f)))
        key = json.dumps(d.get("concolic_seeds"), sort_keys=True)
        out[key] = (f, d)
    return out


def main():
    A, B = sys.argv[1], sys.argv[2]
    a, b = load(A), load(B)
    print(f"A={A}: {len(a)} dumps")
    print(f"B={B}: {len(b)} dumps")
    common = set(a) & set(b)
    print(f"seed-matched: {len(common)}  onlyA={len(set(a)-set(b))}  onlyB={len(set(b)-set(a))}")
    print()

    pc_mismatch = 0
    note_delta = Counter()
    star_a = star_b = 0
    for k in sorted(common):
        fa, da = a[k]
        fb, db = b[k]
        pa, pb = pcs_of(da), pcs_of(db)
        if pa != pb:
            pc_mismatch += 1
            if pc_mismatch <= 3:
                print(f"  PC MISMATCH {fa} vs {fb}: {len(pa)} vs {len(pb)} conds")
        na, nb = notes_of(da), notes_of(db)
        sa, sb = set(na), set(nb)
        for n in sa - sb:
            note_delta[("ONLY_A", "profiles" in n)] += 1
        for n in sb - sa:
            note_delta[("ONLY_B", "profiles" in n)] += 1
        star_a += sum(1 for n in na if 'profiles".*' in n)
        star_b += sum(1 for n in nb if 'profiles".*' in n)

    print(f"PC-identical dumps : {len(common) - pc_mismatch}/{len(common)}")
    print(f"PC-mismatched dumps: {pc_mismatch}")
    print(f"'SELECT profiles.*' note occurrences: A={star_a}  B={star_b}")
    print(f"note set deltas: {dict(note_delta)}")
    print()

    # show one representative profiles note from each side
    for label, side in (("A", a), ("B", b)):
        for k in sorted(common):
            _, d = side[k]
            for n in notes_of(d):
                if "profiles" in n:
                    print(f"  {label} sample: {n[:240]}")
                    break
            else:
                continue
            break


if __name__ == "__main__":
    main()
