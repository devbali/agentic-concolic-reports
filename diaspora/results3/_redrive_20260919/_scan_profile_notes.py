#!/usr/bin/env python3
"""Collect every DISTINCT note mentioning `profiles` across an endpoint corpus,
and classify each as star-projection vs explicit-column-list.

The question this answers: does ANY recorded profiles read derive its
projection from ActiveRecord (and would therefore narrow under a "mod" env), or
are they all hand-synthesised `SELECT "profiles".*` strings from the batch-local
mock layer (in which case RAILS_ENV cannot affect them)?
"""
import json
import os
import re
import sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor


def notes_of(path):
    try:
        d = json.load(open(path, "rb"))
    except Exception:
        return []
    out = []
    for sr in d.get("symbolic_results") or []:
        n = sr.get("note")
        if n and "profiles" in n:
            out.append(n)
    for ev in d.get("events") or []:
        n = ev.get("note")
        if n and "profiles" in n:
            out.append(n)
    return out


def main():
    d = sys.argv[1]
    name = sys.argv[2]
    files = [
        os.path.join(d, f)
        for f in os.listdir(d)
        if f.startswith("dump_") and f.endswith(".json")
    ]
    files.sort()
    distinct = Counter()
    with ProcessPoolExecutor(max_workers=16) as ex:
        for ns in ex.map(notes_of, files, chunksize=64):
            for n in ns:
                distinct[n] += 1

    star = explicit = other = 0
    for n, c in distinct.items():
        m = re.match(r'\s*SELECT\s+(.*?)\s+FROM\s', n, re.S)
        if not m:
            other += 1
            continue
        proj = m.group(1)
        if re.fullmatch(r'"?profiles"?\.\*', proj.strip()):
            star += 1
        elif "profiles" in proj and "." in proj and "*" not in proj:
            explicit += 1
        else:
            other += 1

    print(f"=== {name} ===")
    print(f"  dumps scanned            : {len(files)}")
    print(f"  distinct profiles notes  : {len(distinct)}")
    print(f"  ...bare `profiles.*`     : {star}")
    print(f"  ...explicit column list  : {explicit}")
    print(f"  ...other shape           : {other}")
    print("  top 6 distinct notes:")
    for n, c in distinct.most_common(6):
        print(f"    [{c}x] {n[:170]}")
    if explicit:
        print("  EXPLICIT-LIST samples:")
        shown = 0
        for n in distinct:
            m = re.match(r'\s*SELECT\s+(.*?)\s+FROM\s', n, re.S)
            if m and "profiles" in m.group(1) and "*" not in m.group(1):
                print(f"    {n[:250]}")
                shown += 1
                if shown >= 3:
                    break


if __name__ == "__main__":
    main()
