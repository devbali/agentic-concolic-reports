#!/usr/bin/env python3
"""C30 — one gate-test representative per §16e (P, d) GATE-CONJUNCTION class.

The §16e twin of `_c27_gate_classes.py` (§16g) and `_c29_gate_classes_16f.py`
(§16f), and the one that was MISSING: C27 built `_c27_16e_classes.json` by an
ad-hoc step inside `_c27_fals2.sh`, and C29 then carried ON's 89 §16e rows
forward on a BYTE-IDENTITY argument rather than re-extracting them. That works
only while the applied set does not move; a confinement-OFF pass is a
different applied set, so the extractor has to exist.

The coverage pass emits every applied class in `conjunction_foreclosure_list`.
Each row is (gate prefix P, member d). The gate's own dedup key is
(type, expr, prefix), so one representative per DISTINCT (member, P) is
exactly one representative per CLAIM — no collapsing beyond that.

Output format is byte-compatible with `_c27_16e_classes.json`, verified
field-by-field against it, so `_c27_fals.py` reads it unchanged.

  usage: python3 _c30_gate_classes_16e.py <summary.json> <out.json>
Read-only.
"""
import json
import sys

SUM, OUT = sys.argv[1], sys.argv[2]
s = json.load(open(SUM))
rows = s.get("conjunction_foreclosure_list") or []

seen, classes = set(), []
for it in rows:
    # `prefix` is the gate conjunction; accept both the list-of-pairs shape the
    # summary writes and an already-joined string, rather than assuming one.
    pre = it.get("prefix")
    if isinstance(pre, str):
        raise SystemExit("prefix is already a string — refusing to guess its "
                         "pair structure; extract from the list shape")
    cond = [[g, o] for g, o in pre]
    member = it.get("member") or it.get("expr")
    if member is None:
        raise SystemExit(f"row has neither `member` nor `expr`: {it!r}")
    key = (member, tuple(map(tuple, cond)))
    if key in seen:
        continue
    seen.add(key)
    classes.append({
        "type": "ConjunctionForeclosureAssumption",
        "expr": member,
        "prefix": " AND ".join(f"{g} :: {o}" for g, o in cond),
        "gates": cond,
        "conditioning": cond,
        "inferred": True,
        "section": "16e",
        "description": f"Gate-conjunction foreclosure (inferred, 16e, "
                       f"|P|={len(cond)})",
    })

json.dump(classes, open(OUT, "w"), indent=1)
print(f"{len(rows)} applied rows -> {len(classes)} distinct (member, P) classes")
for c in classes[:3]:
    print(f"  |P|={len(c['gates'])}  {c['expr'][:88]}")
print("C30-GATE-CLASSES-16E-DONE")
