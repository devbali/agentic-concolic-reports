#!/usr/bin/env python3
"""Re-derive H6 (over-emission) against the CORRECTED (DML-aware) ground truth.
Full corpus, all run files, no h6_answered filter. Names its evidence."""
import glob, json, os, re, sys
sys.path.insert(0, "/home/dev/project/reports/diaspora/tools")
from hardening_lint import _is_dml, _shape, WALLS
batch = sys.argv[1].rstrip("/")
runs = sys.argv[2:]
print("   judging runs: " + ", ".join(os.path.basename(r) for r in runs))
real = set()
for rp in runs:
    loaded = json.load(open(rp))
    if isinstance(loaded, dict): loaded = loaded.get("scenarios") or []
    for sc in loaded:
        if not isinstance(sc, dict): continue
        for st in sc.get("statements") or []:
            sql = st["sql"] if isinstance(st, dict) else st
            real.add(_shape(sql))
notes_by_target = {}
files = sorted(glob.glob(os.path.join(batch, "dump_*.json")))
for p in files:
    try: d = json.load(open(p))
    except Exception: continue
    for e in d.get("events") or []:
        if e.get("type") != "symbolic_call": continue
        nt = e.get("note") or ""
        if not _is_dml(nt): continue
        notes_by_target.setdefault(str(e.get("target") or ""), {}).setdefault(_shape(nt), [0, nt])[0]
        r = notes_by_target[str(e.get("target") or "")][_shape(nt)]
        r[0] += 1
print(f"== H6 re-derivation over {len(files)} dumps, {len(real)} distinct real shapes ==")
un = 0
for t, shapes in sorted(notes_by_target.items()):
    for sh, (cnt, nt) in sorted(shapes.items()):
        if sh not in real:
            un += 1
            print(f"  UNISSUED  x{cnt:<7d} {t}\n            {re.sub(chr(10),' ',nt)[:150]}")
print(f"\nunissued note shapes (corpus-wide, all runs): {un}")
