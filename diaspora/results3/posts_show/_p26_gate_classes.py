#!/usr/bin/env python3
"""P26 step B1 — the gate's DECLARED list: one representative per confinement
CLASS, from the P25OR pass's own `summary["assumptions"]`.

DISCIPLINE §16c check 2 tests one representative per footprint-family class and
withdraws every pair in a non-PASS class with it (§82.5: 2 701 inferred pairs ->
1 363 classes). The class key is `notifications_index/_c11_classes.py::class_of`
(READ, not edited, not imported), reproduced here verbatim.

    SUMMARY=<coverage summary json> OUT=<declared.json> META=<meta.json>
        python3 -u _p26_gate_classes.py

Verdict line: `P26-CLASSES-DONE`.
"""
import json
import os
import re
import sys
from collections import Counter

B = os.path.dirname(os.path.abspath(__file__))
SUMMARY = os.environ.get("SUMMARY", os.path.join(B, "_cov_FINAL_P25OR_20260912.json"))
OUT = os.environ.get("OUT", os.path.join(B, "_p26_gate_classes.json"))
META = os.environ.get("META", os.path.join(B, "_p26_gate_classes_meta.json"))

# ---- _c11_classes.py::side_key / class_of, verbatim ------------------------
TBL = re.compile(r"(?:records|to_ary)_([a-z_]+?)_[0-9a-f]{8}")


def side_key(expr, footprint):
    if footprint:
        return tuple(sorted(s[:60] for s in footprint))
    m = TBL.search(expr)
    return (m.group(1),) if m else (expr[:60],)


def class_of(a):
    ka = side_key(a["expr_a"], a.get("footprint_a") or [])
    kb = side_key(a["expr_b"], a.get("footprint_b") or [])
    return str(tuple(sorted((ka, kb))))


print(f"reading {SUMMARY} ({os.path.getsize(SUMMARY)/1e6:.0f} MB)", flush=True)
S = json.load(open(SUMMARY))
A = S.get("assumptions") or []
print(f"  assumptions {len(A)}: {dict(Counter(x.get('type') for x in A))}", flush=True)
conf = [a for a in A if a.get("type") == "ConfinementAssumption"]
inferred = sum(1 for a in conf if a.get("inferred"))
print(f"  ConfinementAssumption {len(conf)} (inferred={inferred})", flush=True)
del S

part = {}
for a in conf:
    part.setdefault(class_of(a), []).append(a)
print(f"  CLASSES {len(part)}; largest {max((len(v) for v in part.values()), default=0)} pairs",
      flush=True)

# representative = the FIRST pair of the class in a deterministic order, so a
# relaunch tests the same reps and the checkpoint keys line up.
reps, meta = [], []
for k in sorted(part):
    members = sorted(part[k], key=lambda a: (a["expr_a"], a["expr_b"]))
    r = dict(members[0])
    reps.append(r)
    meta.append({"tier": "confinement", "class": k, "covers": len(members)})
json.dump(reps, open(OUT, "w"), indent=1)
json.dump(meta, open(META, "w"), indent=1)
print(f"  wrote {len(reps)} representatives -> {OUT}")
print(f"  wrote meta                        -> {META}")
sz = Counter(len(v) for v in part.values())
print("  class-size histogram: " + " ".join(f"{n}x{c}" for n, c in sorted(sz.items())[:12]))
print("P26-CLASSES-DONE", flush=True)
