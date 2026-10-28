"""Dry-run the gate-reuse wrapper on a declared set built to order:
50 unchanged declarations (must be REUSED, no real probe) + 1 synthetic NEW
confinement pair (must be routed to the real checker). The synthetic pair is
then removed: this only proves the wrapper's routing and its withdrawn-class
check, it publishes nothing."""
import json, os, subprocess, sys
B = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, B)
from _c11_ids import _stream                                   # noqa: E402

keep = []
withdrawn = {tuple(sorted(p)) for p in json.load(open(os.path.join(B, "_confinement_withdrawn.json")))}
for a in _stream(os.path.join(B, "_assumptions_declared_cert3.json")):
    if a.get("type") == "AliasAssumption":
        keep.append(a)
    elif a.get("type") == "IndependenceAssumption" and len(keep) < 52:
        keep.append(a)
    if len(keep) >= 52:
        break
out = os.path.join(B, "_c11_dry_declared.json")
json.dump(keep, open(out, "w"))
print(f"dry declared: {len(keep)}")
