#!/usr/bin/env python3
"""Corpus family audit: count & sample the 4 sanctioned families in the
fresh corpus + verify the warden users-load is the FIRST statement of each
signed-in run (pre-entrypoint evidence), and locate owner_id shapes."""
import glob
import json
import os
import re
from collections import Counter, defaultdict

BATCH = "/home/dev/project/reports/diaspora/results3/people_show"
RUNS = os.path.join(BATCH, "adversary", "runs")

# ---- 1. corpus family counts ----
fam = Counter()
owner_notes = []
update_notes = []
pluck_notes = []
exists_notes = []
for f in glob.glob(os.path.join(BATCH, "dump_*.json")):
    d = json.load(open(f))
    for ev in d.get("events") or []:
        if ev.get("type") != "symbolic_call" or not ev.get("result_name"):
            continue
        t = str(ev.get("target") or "").replace("#", ".")
        n = str(ev.get("note") or "")
        s = n.strip()
        if s.startswith("UPDATE") and "notifications" in s.lower():
            fam["P1 UPDATE notifications"] += 1
            if len(update_notes) < 3:
                update_notes.append((t, n))
        elif "exists?" in t:
            fam["P2 exists? target"] += 1
            if len(exists_notes) < 3:
                exists_notes.append((t, n[:140]))
        elif t.startswith("ActiveRecord::Calculations.pluck"):
            fam["P9 pluck"] += 1
            if len(pluck_notes) < 3:
                pluck_notes.append((t, n[:160]))
        elif "owner_id" in s.lower():
            fam["P10 owner_id note"] += 1
            if len(owner_notes) < 8:
                owner_notes.append((t, n[:160]))
# also check symbolic_vars carrying notes (P-2 exists? notes live on vars sometimes)
var_exists = 0
for f in glob.glob(os.path.join(BATCH, "dump_*.json")):
    d = json.load(open(f))
    for sv in d.get("symbolic_vars") or []:
        nm = str(sv.get("name") or "")
        note = str(sv.get("note") or "")
        if "exists?" in nm and note.strip():
            var_exists += 1
        if "owner_id" in note.lower() and len(owner_notes) < 8:
            owner_notes.append(("VAR:" + nm[:60], note[:160]))

print("== corpus family counts ==")
for k, v in sorted(fam.items()):
    print(f"  {k}: {v}")
print(f"  P2 exists? var-carried notes: {var_exists}")
print()
print("== P1 UPDATE notifications samples ==")
for t, n in update_notes:
    print(f"  [{t}] {n[:170]}")
print()
print("== P2 exists? samples ==")
for t, n in exists_notes:
    print(f"  [{t}] {n}")
print()
print("== P9 pluck samples ==")
for t, n in pluck_notes:
    print(f"  [{t}] {n}")
print()
print("== P10 owner_id samples ==")
for t, n in owner_notes[:10]:
    print(f"  [{t}] {n}")

# ---- 2. warden users-load position in each signed-in run ----
print()
print("== users-load position in real runs ==")
for f in sorted(glob.glob(os.path.join(RUNS, "C*.json"))):
    name = os.path.basename(f)
    for sc in json.load(open(f)):
        stmts = sc.get("statements") or []
        for i, st in enumerate(stmts):
            sql = st["sql"]
            if sql.strip().startswith('SELECT  "users".* FROM "users"') or \
               sql.strip().startswith('SELECT "users".* FROM "users"'):
                print(f"  {name}: users-load at stmt #{i} of {len(stmts)} "
                      f"under={st.get('under')} | first={stmts[0]['sql'][:70] if i==0 else stmts[0]['sql'][:70]}")
                break

# ---- 3. owner_id in real runs ----
print()
print("== owner_id / author_id statements in real runs ==")
for f in sorted(glob.glob(os.path.join(RUNS, "C*.json"))):
    name = os.path.basename(f)
    for sc in json.load(open(f)):
        for st in sc.get("statements") or []:
            sql = st["sql"]
            if "owner_id" in sql or ("author_id" in sql):
                print(f"  {name}: [{st.get('under')}] {sql[:150]}")