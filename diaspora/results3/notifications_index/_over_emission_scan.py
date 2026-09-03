#!/usr/bin/env python3
"""Over-emission scan (coordinator, 2026-08-28): every distinct NOTE SHAPE in
the corpus that no real statement of the concrete runs matches. A note with no
real counterpart is a Class-S mis-shape in the other direction — it inflates
the extracted policy with an access the endpoint cannot perform."""
import json, glob, os, re, collections, sys
HERE = os.path.dirname(os.path.abspath(__file__))

def shape(sql):
    s = re.sub(r"\$\$\([^)]*\)", "?", str(sql))
    s = re.sub(r"'[^']*'", "'?'", s)
    s = re.sub(r"\b\d+\b", "?", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"IN \((\?, )*\?\)", "IN (?)", s)
    return s

real = collections.Counter()
for run in glob.glob(os.path.join(HERE, "concrete_run*.json")):
    for scen in json.load(open(run)):
        for st in (scen.get("statements") or []):
            real[shape(st.get("sql") if isinstance(st, dict) else st)] += 1

corpus = collections.Counter()
files = glob.glob(os.path.join(HERE, "dump_*.json"))
for p in files:
    for e in json.load(open(p)).get("events", ()):
        n = e.get("note")
        if isinstance(n, str) and n.lstrip().upper().startswith("SELECT"):
            corpus[shape(n)] += 1

print(f"corpus note shapes: {len(corpus)}   real statement shapes: {len(real)}   dumps: {len(files)}")
missing = [(c, s) for s, c in corpus.items() if s not in real]
missing.sort(reverse=True)
print(f"\n-- corpus note shapes with NO real counterpart: {len(missing)} --")
for c, s in missing[:25]:
    print(f"{c:8d}  {s[:150]}")
unseen = [(c, s) for s, c in real.items() if s not in corpus]
print(f"\n-- real statement shapes with NO corpus note: {len(unseen)} --")
for c, s in unseen[:15]:
    print(f"{c:8d}  {s[:150]}")
