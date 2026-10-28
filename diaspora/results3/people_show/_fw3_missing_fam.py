#!/usr/bin/env python3
"""Compare the MISSING set between the baseline (committed summary at fa9e4aa
had 64 but the file was overwritten — we have the drained corpus summary from
69fe5bb committed value 64) against the current mixed-corpus coverage_summary.

Because coverage_summary.json was overwritten, reconstruct baseline missing
from git OR re-run on baseline-only. Here: compare the CURRENT mixed summary's
missing list shape vs what we can extract. Print families of the current 64.
"""
import json, re, collections

d = json.load(open("/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"))
print("endpoint:", d.get("endpoint"), "| complete:", d.get("coverage_complete"),
      "| MISSING:", d.get("missing_branches"), "| NODES:", d.get("tree_nodes"),
      "| runs:", d.get("total_runs"), "| PCS:", d.get("total_path_conditions"))
m = d.get("missing", [])
print("missing entries:", len(m))

def family(expr):
    s = str(expr)
    if "records_1_rows" in s or "to_a_1_rows" in s or "records_2_rows" in s or "records_3_rows" in s:
        return "rows/stream"
    if "records_1" in s or "records_2" in s:
        return "bare_records"
    if "guard" in s or "stream" in s:
        return "guard/stream"
    if "_row_" in s:
        return "row_attr"
    return "other:" + s[:40]

fam = collections.Counter()
samples = collections.defaultdict(list)
for x in m:
    ex = x if isinstance(x, str) else repr(x)
    f = family(ex)
    fam[f] += 1
    if len(samples[f]) < 3:
        samples[f].append(ex[:150])
for f, c in fam.most_common():
    print(f"\n[{f}] x{c}")
    for s in samples[f]:
        print("   ", s)