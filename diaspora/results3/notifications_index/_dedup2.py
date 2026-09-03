#!/usr/bin/env python3
"""Corpus hygiene, EVIDENCE-PRESERVING key: (variant, terminal error, ORDERED
path, NOTE multiset). Seeds and scenario are deliberately NOT in the key — two
dumps with the same path AND the same notes carry the same evidence for every
check that reads the corpus (coverage tree, note check, all ten audits); only
the assumption gate's snapshot CHOICE sees seeds, and each surviving dump keeps
its own. Dropping them is what keeps the engine report inside its memory
budget: 43 519 runs put the completion section over MemoryMax=6G.
"""
import glob, json, os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.join(HERE, "_dup_path_dumps")
os.makedirs(DEST, exist_ok=True)
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
seen, kept, moved = set(), 0, 0
for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json"))):
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), "?")
    try:
        d = json.load(open(p))
    except Exception:
        continue
    evs = d.get("events") or ()
    sig = (v,
           d.get("error", {}).get("type") if isinstance(d.get("error"), dict) else None,
           tuple((e["expr"], bool(e.get("taken"))) for e in evs if e.get("type") == "path_condition"),
           tuple(sorted(str(e.get("note") or "") for e in evs if e.get("type") == "symbolic_call")))
    if sig in seen:
        shutil.move(p, os.path.join(DEST, base)); moved += 1
    else:
        seen.add(sig); kept += 1
    del d
print(f"dedup2: kept {kept}, moved {moved} (same variant+path+notes)")
