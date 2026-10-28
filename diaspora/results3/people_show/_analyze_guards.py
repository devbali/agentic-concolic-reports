#!/usr/bin/env python3
"""Analyze the 64 missing combos' SAT models: how many force guards
(closed_account=True / not_found=True) that would foreclose the branch?"""
import json

s = json.load(open("/tmp/per_item_sat.json"))
rows = s["rows"]
print("rows:", len(rows))

def model_has(model, substr):
    return any(k.endswith(substr) and v is True for k, v in model.items())

stats = {"closed_account": 0, "not_found": 0, "either": 0, "neither": 0}
models_clean = []
for r in rows:
    m = r.get("model") or {}
    ca = model_has(m, "closed_account")
    nf = model_has(m, "not_found")
    if ca: stats["closed_account"] += 1
    if nf: stats["not_found"] += 1
    if ca or nf:
        stats["either"] += 1
    else:
        stats["neither"] += 1
        models_clean.append(r)

print("model guard analysis (any closed_account=True / not_found=True in model):")
print("  closed_account=True :", stats["closed_account"])
print("  not_found=True      :", stats["not_found"])
print("  either guard        :", stats["either"])
print("  neither guard       :", stats["neither"])

# show the clean ones' constraints
print("\n=== items with NEITHER guard in model (n=%d) ===" % len(models_clean))
for r in models_clean:
    print("idx", r["idx"], "| pcs-scored:", r.get("node_constraint", "")[:200])