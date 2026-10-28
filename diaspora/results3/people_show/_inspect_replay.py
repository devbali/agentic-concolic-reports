#!/usr/bin/env python3
"""Inspect per-item SAT result + concrete_values structure for the replay."""
import json, os, sys

base = "/home/dev/project/reports/diaspora/results3/people_show"

# 1. per-item result
pit = "/tmp/per_item_sat.json"
if os.path.exists(pit):
    with open(pit) as fh:
        per = json.load(fh)
    print("PER-ITEM FILE:", pit)
    print("  entries:", type(per).__name__, len(per) if not isinstance(per, dict) else list(per.keys()))
    if isinstance(per, list) and per:
        print("  first sample:", json.dumps(per[0])[:400])
    elif isinstance(per, dict):
        for k in list(per)[:3]:
            print("  ", k, "=>", json.dumps(per[k])[:200])
else:
    print("NO per-item file yet:", pit)

# 2. coverage summary missing items -> concrete_values structure
summ = os.path.join(base, "coverage_summary.json")
if os.path.exists(summ):
    with open(summ) as fh:
        s = json.load(fh)
    print("\nCOVERAGE_SUMMARY keys:", list(s.keys()))
    miss = s.get("missing") or s.get("missing_combos") or []
    print("  missing count:", len(miss))
    if miss:
        m0 = miss[0]
        print("  missing[0] keys:", list(m0.keys()))
        for kv in ["node_constraint", "concrete_values", "source_location", "clique"]:
            if kv in m0:
                v = m0[kv]
                print(f"  {kv}: {json.dumps(v)[:300]}")
        # count keys used as seed vars
        cv = m0.get("concrete_values")
        if isinstance(cv, dict):
            print("  concrete_values keys (%d):" % len(cv))
            for kk in list(cv)[:60]:
                print("     ", kk, "=", repr(cv[kk]))
        elif isinstance(cv, list):
            print("  concrete_values is a LIST of", len(cv))
            for it in cv[:20]:
                print("     ", json.dumps(it)[:200])
else:
    print("NO coverage_summary.json at", summ)
