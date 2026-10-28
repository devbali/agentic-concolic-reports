#!/usr/bin/env python3
"""Diff the baseline MISSING set (from git 69fe5bb) against the mixed-corpus
MISSING set (current coverage_summary.json) by node_constraint signature."""
import json, subprocess, hashlib

def load_git(rev, path):
    raw = subprocess.run(["git","show",f"{rev}:{path}"], capture_output=True, text=True, cwd="/home/dev/project/reports")
    return json.loads(raw.stdout)

def sigs_of(d):
    out = set()
    for x in d.get("missing", []):
        if isinstance(x, dict):
            c = x.get("node_constraint") or x.get("constraint") or json.dumps(x, sort_keys=True)
        else:
            c = str(x)
        out.add(c)
    return out

base = load_git("69fe5bb", "diaspora/results3/people_show/coverage_summary.json")
cur  = json.load(open("/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"))

bs, cs = sigs_of(base), sigs_of(cur)
print("baseline sigs:", len(bs), "| mixed sigs:", len(cs))
cleared = bs - cs
appeared = cs - bs
common = bs & cs
print(f"cleared (baseline only): {len(cleared)}")
print(f"appeared (mixed only):  {len(appeared)}")
print(f"common (both):          {len(common)}")
print("\n=== CLEARED (baseline missing, now witnessed) ===")
for s in sorted(cleared)[:70]:
    print("  ", s[:160])
print("\n=== APPEARED (newly missing) ===")
for s in sorted(appeared)[:40]:
    print("  ", s[:160])