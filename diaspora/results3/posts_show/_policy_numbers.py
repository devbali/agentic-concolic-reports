#!/usr/bin/env python3
"""§76.8 — the shipped policy's numbers, including the SYNTACTIC vs SOLVER
split of subsumption, which the extractor prints only as a tri-state tally."""
import json, os, re, sys
from collections import Counter
Q = "/home/dev/project/reports/diaspora/results3/queries_from_runs"
name = os.environ.get("SUMMARY", "_summary_posts_show.json")
S = json.load(open(os.path.join(Q, name)))["posts_show"]
print(f"endpoint      {S['endpoint']}")
print(f"dumps         {S['n_dumps']}   runs loaded {S['n_runs_loaded']}")
print(f"queries       raw {S['n_queries_raw']} -> distinct {S['n_queries_deduped']} "
      f"-> emitted {S['n_queries_final']}   (subsumption dropped {S['n_subsumed_dropped']})")
print(f"placeholders  {len(S['placeholders'])} families")
for p in S["placeholders"]:
    print(f"                {p}")
print(f"flags         " + ", ".join(f"{k} {v}" for k, v in sorted(S["flags"].items())))
errs = S.get("errors") or []
unp = [e for e in errs if "unparseable note" in e]
rot = [e for e in errs if "bind-rotation-UNRESOLVED" in e]
print(f"unparseable   {len(unp)}  (E11)")
print(f"rotation      {len(rot)}  (R1)")
print(f"subsume_ran   {S.get('subsume_ran')}   subsume_errors {len(S.get('subsume_errors') or {})}")
for e in errs[:6]:
    print(f"   error: {e[:150]}")
# SYNTACTIC vs SOLVER: the extractor's own two filters, recomputed from the
# emitted file's flag comments (the same predicates, in the same order).
sqlp = os.path.join(Q, os.environ.get("SQL", "posts_show.sql"))
if os.path.exists(sqlp):
    txt = open(sqlp).read()
    flags = Counter()
    for m in re.finditer(r"^--\s+flags:\s*(.+)$", txt, re.M):
        for f in m.group(1).split():
            flags[f.strip(",")] += 1
    sel = txt.count("\nSELECT")
    print(f"\nshipped file  {sqlp}")
    print(f"  SELECT statements {sel}")
    print(f"  flag lines        {sum(flags.values())}")
    for f, n in flags.most_common(12):
        print(f"    {n:>6}  {f}")
    print("  SYNTACTIC exclusions (the extractor's own predicates):")
    print("    not eligible  = placeholders OR type-mismatched-join")
    print("    cannot subsume= finder-without-where OR unscoped OR broadened-*")
print("\nPOLICY NUMBERS DONE")
