#!/usr/bin/env python3
"""P32 — CLASS-WHOLE withdrawal of every non-PASS confinement class.

Policy (not invented here): `coverage_report.py` states it in the comment above
`withdrawn_pairs=` — "CLASS-WHOLE: the gate tests one representative per
footprint-family class and every pair in a non-PASS class is withdrawn with
it", which is notifications' precedent. NON-PASS = FAIL + NOT-TESTABLE +
NOT-COMPARABLE: a gate verdict is replay evidence and outranks corpus
inference, and an untested/untestable class has produced NO evidence, so it
cannot carry a licence either.

class_of is `_p26_gate_classes.py`'s, which is `_c11_classes.py::class_of`
verbatim. Read-only except for OUT.
"""
import json, os, re, sys
from collections import Counter, defaultdict

B = os.path.dirname(os.path.abspath(__file__))
SUMMARY = os.environ.get("SUMMARY", os.path.join(B, "_cov_FINAL_P31AB2_20260913.json"))
OUT = os.environ.get("OUT", os.path.join(B, "_confinement_withdrawn.json"))
REPORT = os.environ.get("REPORT", os.path.join(B, "_p32_withdraw_report.json"))

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

res = json.load(open(os.path.join(B, "_p26_gate_results.json")))
dec = json.load(open(os.path.join(B, "_p26_gate_classes.json")))
verdict_by_key = {(r["expr"], r["expr_b"]): r["verdict"] for r in res}
cls_verdict, cls_detail = {}, {}
for d in dec:
    k = (d["expr_a"], d["expr_b"])
    v = verdict_by_key.get(k)
    if v is None:
        continue
    c = class_of(d)
    cls_verdict[c] = v
    cls_detail[c] = next((r.get("detail") for r in res if (r["expr"], r["expr_b"]) == k), "")
print(f"gate classes with a verdict: {len(cls_verdict)} of {len(dec)} declared", flush=True)
print("verdicts:", dict(Counter(cls_verdict.values())), flush=True)

print(f"reading {SUMMARY} ({os.path.getsize(SUMMARY)/1e6:.0f} MB)", flush=True)
S = json.load(open(SUMMARY))
A = S.get("assumptions") or []
print(f"assumptions in summary: {len(A)}", flush=True)

withdrawn, kept, untested = [], 0, 0
by_verdict = Counter(); fam = Counter(); untested_cls = Counter()
for a in A:
    if a.get("type") != "ConfinementAssumption":
        continue
    c = class_of(a)
    v = cls_verdict.get(c)
    if v is None:
        untested += 1; untested_cls[c] += 1; continue
    if v == "PASS":
        kept += 1; continue
    withdrawn.append([a["expr_a"], a["expr_b"]])
    by_verdict[v] += 1
    fam[(v, (cls_detail.get(c) or "")[:60])] += 1

# dedupe, order-insensitive, matching the engine's own tuple(sorted(p))
seen, uniq = set(), []
for p in withdrawn:
    t = tuple(sorted(p))
    if t not in seen:
        seen.add(t); uniq.append(list(p))
json.dump(uniq, open(OUT, "w"), indent=0)
rep = {
    "pairs_withdrawn": len(uniq), "pairs_kept_PASS": kept,
    "pairs_in_untested_class": untested,
    "withdrawn_by_verdict": dict(by_verdict),
    "untested_classes": len(untested_cls),
    "top_families": [[f"{v} | {d}", n] for (v, d), n in fam.most_common(12)],
}
json.dump(rep, open(REPORT, "w"), indent=1)
print(json.dumps(rep, indent=1))
print(f"wrote {OUT} ({len(uniq)} pairs)")
print("P32-WITHDRAW-DONE")
