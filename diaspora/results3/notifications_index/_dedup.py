#!/usr/bin/env python3
"""Corpus hygiene: move dumps whose (variant, PC-signature) is already present
into _dup_path_dumps/. SEEDS_ONLY / rooted replays write one dump per root, so
the corpus accumulates duplicate PATHS across launches; the coverage tree and
the assumption gate read nothing a duplicate path adds, and the dedup roughly
halves peak RSS. Verified on cycle 2: BLOCKING identical before/after.
"""
import glob, json, os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.join(HERE, "_dup_path_dumps")
os.makedirs(DEST, exist_ok=True)
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
seen = set()
kept = moved = 0
for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json"))):
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), "?")
    try:
        d = json.load(open(p))
    except Exception:
        continue
    # Coordinator key (2026-08-29): variant + ORDERED PATH + NOTE MULTISET +
    # SEEDS + SCENARIO. Deduplicating on the path alone would drop dumps whose
    # NOTES differ, and the note-based audits read the dump FILES — so the note
    # multiset is part of the identity, not just the path.
    evs = d.get("events") or ()
    sig = (v,
           d.get("error", {}).get("type") if isinstance(d.get("error"), dict) else None,
           tuple((e["expr"], bool(e.get("taken")))
                 for e in evs if e.get("type") == "path_condition"),
           tuple(sorted(str(e.get("note") or "") for e in evs
                        if e.get("type") == "symbolic_call")),
           json.dumps(d.get("concolic_seeds") or {}, sort_keys=True),
           json.dumps(d.get("concolic_scenario") or {}, sort_keys=True))
    if sig in seen:
        shutil.move(p, os.path.join(DEST, base))
        moved += 1
    else:
        seen.add(sig)
        kept += 1
print(f"dedup: kept {kept}, moved {moved} duplicate-path dumps to _dup_path_dumps/")
