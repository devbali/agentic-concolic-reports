#!/usr/bin/env python3
"""P40b — per-PAIR gate verdict AND refutation SHAPE for the 564 withdrawals.

Same class map as `_p40_pairsplit.py`; adds the reason bucket so a later census
can ask what each SHAPE of refutation costs.  Buckets:

  REMOVAL   "(iv) flip-X leaves Y UNEVALUATED" — removal-shaped dependence.
            X11/DISCIPLINE §16b: this is FORECLOSURE, not a confinement
            refutation, and withdrawing the licence on it inflates demand in
            the direction the truth shrinks it.
  DOWNSTREAM "(iv) flip-X changed Y's outcome" — genuine additive dependence.
  LEAK      "(i) flip-X changed a shape OUTSIDE footprint(X)" — the footprint
            was measured too small; genuine refutation of §16c's premise.
  OTHER     anything else.

Writes `_p40_pair_reasons.json`.  Verdict line: `P40B-DONE`.
"""
import json, os, re, collections
B = os.path.dirname(os.path.abspath(__file__))
TBL = re.compile(r"(?:records|to_ary)_([a-z_]+?)_[0-9a-f]{8}")
def side_key(expr, fp):
    if fp: return tuple(sorted(s[:60] for s in fp))
    m = TBL.search(expr); return (m.group(1),) if m else (expr[:60],)
def class_of(a):
    return str(tuple(sorted((side_key(a["expr_a"], a.get("footprint_a") or []),
                             side_key(a["expr_b"], a.get("footprint_b") or [])))))
def bucket(d):
    d = d or ""
    if "UNEVALUATED" in d: return "REMOVAL"
    if "changed A's outcome" in d or "changed B's outcome" in d: return "DOWNSTREAM"
    if "OUTSIDE footprint" in d: return "LEAK"
    return "OTHER"
PIN_A, PIN_B = "findpublic_like_1_not_found", "as_api_response_1_row_text_empty"
vb, db = {}, {}
for r in json.load(open(f"{B}/_p26_gate_results.json")):
    vb[(r["expr"], r["expr_b"])] = r["verdict"]; db[(r["expr"], r["expr_b"])] = r.get("detail", "")
for f in ("_p32_regate_results.json", "_p32_regate_NC_results.json"):
    for r in json.load(open(f"{B}/{f}")):
        k = (r["expr"], r["expr_b"])
        vb[k] = "PASS" if (r["verdict"] == "PASS" and (r.get("bases_realising") or 0) >= 1) else r["verdict"]
        db[k] = r.get("detail", "")
cls_v, cls_d, cls_k = {}, {}, {}
for d in json.load(open(f"{B}/_p26_gate_classes.json")):
    k = (d["expr_a"], d["expr_b"])
    if k in vb:
        c = class_of(d); cls_v[c] = vb[k]; cls_d[c] = db[k]; cls_k[c] = k
pin = [c for c, k in cls_k.items() if (PIN_A in k[0] and PIN_B in k[1]) or (PIN_A in k[1] and PIN_B in k[0])]
assert len(pin) == 1
cls_v[pin[0]] = "FAIL"; cls_d[pin[0]] = "(i) flip-A changed 1 shape(s) OUTSIDE footprint(A): Photo.url [PINNED]"

W = set(tuple(sorted(p)) for p in json.load(open(f"{B}/_confinement_withdrawn.json")))
out = {}
for a in json.load(open(f"{B}/_cov_FINAL_P31AB2_20260913.json")).get("assumptions") or []:
    if a.get("type") != "ConfinementAssumption": continue
    p = tuple(sorted((a["expr_a"], a["expr_b"])))
    if p not in W: continue
    c = class_of(a); v = cls_v.get(c)
    if v is None: continue
    out["\x00".join(p)] = {"verdict": v, "shape": bucket(cls_d.get(c)) if v.startswith("FAIL") else "UNEVIDENCED"}
print("pairs:", len(out))
print("by verdict:", dict(collections.Counter(v["verdict"] for v in out.values())))
print("by shape:  ", dict(collections.Counter(v["shape"] for v in out.values())))
json.dump(out, open(f"{B}/_p40_pair_reasons.json", "w"), indent=0)
print("P40B-DONE")
