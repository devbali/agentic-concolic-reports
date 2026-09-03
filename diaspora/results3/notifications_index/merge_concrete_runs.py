#!/usr/bin/env python3
"""Merge the per-scenario concrete runs (one manifest per process for JVM
crash isolation) into the single concrete_run.json the note check / fidelity
audit point at. Pure concatenation."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
out = []
for name in ("concrete_run_auth.json", "concrete_run_mobile.json",
             "concrete_run_links.json", "concrete_run_photo.json",
             "concrete_run_pages.json"):
    p = os.path.join(HERE, name)
    if os.path.exists(p):
        out += json.load(open(p))
    else:
        print(f"[merge] missing {name}", file=sys.stderr)
json.dump(out, open(os.path.join(HERE, "concrete_run.json"), "w"), indent=1)
print(f"merged {len(out)} scenario(s) -> concrete_run.json")
