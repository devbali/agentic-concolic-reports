#!/usr/bin/env python3
"""Enumerate the guard-family exprs in the 64 missing items: which finder
slots (_1/_2/...) and which guard sides (not_found/closed_account) appear,
and how often. This tells us exactly which independence/foreclosure
assumptions to add for the mobile-leg (ordinal 2) finders."""
import json
import re
from collections import Counter, defaultdict

items = json.load(open("/tmp/per_item_sat.json"))["rows"]
print(f"{len(items)} missing items\n")

# expr-level: what guard vars force True in each item's model?
guard_re = re.compile(r"(SYM_(?:RESULT_ActiveRecord__FinderMethods_first_\d+|PERSON)_via_\w+_(?:closed_account|not_found))|(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_\d+_not_found)")

slot_outcomes = Counter()      # slot -> Counter(outcome)
item_slots = []                # per-item set of (slot, side) True-assignments
for it in items:
    model = it.get("model") or {}
    trues = {}
    for k, v in model.items():
        if v is True and ("not_found" in k or "closed_account" in k):
            # normalize slot
            mslot = re.search(r"(FinderMethods_first_\d+|Core__ClassMethods_find_by_\d+)", k)
            side = "not_found" if "not_found" in k else "closed_account"
            slot = mslot.group(1) if mslot else k
            key = f"{slot}:{side}"
            slot_outcomes[key] += 1
            trues[key] = True
    item_slots.append(trues)

print("=== guard-side vars forced True across models ===")
for k, v in sorted(slot_outcomes.items()):
    print(f"  {k:70s} {v}")

# per-item: do not_found and closed_account co-occur on the same slot?
print("\n=== per-item not_found AND closed_account co-occurrence (same slot) ===")
co = Counter()
for trues in item_slots:
    slots = set(k.split(":")[0] for k in trues)
    for s in slots:
        nf = f"not_found" in str([x for x in trues if x.startswith(s)])
    both = any("not_found" in k and k.replace("not_found","closed_account") in trues for k in trues)
    co[("both" if both else "one_side")] += 1
print("  ", dict(co))

# distinct combos for a sample item
print("\n=== sample item 0 trues ===")
print(json.dumps(sorted(item_slots[0].keys()), indent=1))