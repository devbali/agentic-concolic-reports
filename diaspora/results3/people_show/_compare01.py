#!/usr/bin/env python3
"""Compare one replay dump's actual path conditions vs its demanded node_constraint."""
import json

# item 0: dump_replay_000.json vs per_item_sat rows[0]
dump = json.load(open("dump_replay_000.json"))
sat = json.load(open("/tmp/per_item_sat.json"))
row = sat["rows"][0]

pcs = []
for e in dump.get("events", []):
    if e.get("type") == "path_condition":
        pcs.append((e.get("expr"), e.get("taken")))

print("=== DUMP events: %d, pcs: %d ===" % (len(dump.get("events", [])), len(pcs)))
print("dump error:", dump.get("error"))
for expr, taken in pcs:
    print(f"  {'T' if taken else 'F'}  {expr}")

print("\n=== DEMANDED node_constraint (SAT rows[0]) ===")
print(row["node_constraint"])

print("\n=== STORED CONCRETE VALUES (model) ===")
print(json.dumps(row.get("model"), indent=1)[:2000])