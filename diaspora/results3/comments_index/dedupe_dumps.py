#!/usr/bin/env python3
"""Remove EXACT-duplicate dump files (coordinator note, 2026-08-29:
"a dump count is not a corpus" — conversations_index carried 41 753 exact
duplicates of 60 078 files, which is what OOM-killed their coverage pass).

Two dumps are the same OBSERVATION when they agree on variant/scenario, the
recorded path signature (expr:taken in order), the SELECT-note multiset, the
recorded terminal and the seed dict. The demand/targeted rounds replay the
same roots repeatedly, so they mint thousands of these.

Nothing the checkers read is lost: the coverage tree, the note check, the
assumption gate and every audit are functions of the DISTINCT observations.

    python3 dedupe_dumps.py [--dry-run]
"""
import glob
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def key_of(d):
    pcs = "|".join(f"{e['expr']}:{bool(e.get('taken'))}"
                   for e in (d.get("events") or []) if e.get("type") == "path_condition")
    notes = sorted(re.sub(r"\s+", " ", str(e.get("note") or ""))
                   for e in (d.get("events") or [])
                   if e.get("type") == "symbolic_call" and str(e.get("note") or "").lstrip().upper().startswith("SELECT"))
    blob = json.dumps({
        "scenario": d.get("concolic_scenario"),
        "terminal": d.get("concolic_terminal"),
        "seeds": d.get("concolic_seeds"),
        "pcs": pcs,
        "notes": notes,
        "error": (d.get("error") or {}).get("type"),
    }, sort_keys=True)
    return hashlib.md5(blob.encode()).hexdigest()


def main():
    dry = "--dry-run" in sys.argv
    seen, dropped, kept = {}, [], 0
    for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json"))):
        try:
            d = json.load(open(p))
        except Exception:
            continue
        k = key_of(d)
        if k in seen:
            dropped.append(p)
        else:
            seen[k] = p
            kept += 1
        del d
    print(f"distinct observations: {kept} | exact duplicates: {len(dropped)}")
    if not dry:
        for p in dropped:
            os.remove(p)
        print(f"removed {len(dropped)} duplicate dump files")


if __name__ == "__main__":
    main()
