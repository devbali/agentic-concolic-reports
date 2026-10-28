#!/usr/bin/env python3
"""P40a — classify each of the 564 still-withdrawn pairs by its GATE VERDICT.

Same class_of / override order as `_p34_withdraw_v2.py`; nothing is hand-typed.
Writes `_p40_pair_verdicts.json`: {"<a>\\x00<b>": verdict}.  Verdict line:
`P40A-DONE`.
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
PIN_A, PIN_B = "findpublic_like_1_not_found", "as_api_response_1_row_text_empty"
vb = {}
for r in json.load(open(f"{B}/_p26_gate_results.json")):
    vb[(r["expr"], r["expr_b"])] = r["verdict"]
regate = {}
for f in ("_p32_regate_results.json", "_p32_regate_NC_results.json"):
    for r in json.load(open(f"{B}/{f}")):
        k = (r["expr"], r["expr_b"])
        regate[k] = r
        vb[k] = "PASS" if (r["verdict"] == "PASS" and (r.get("bases_realising") or 0) >= 1) else r["verdict"]
cls_v, cls_k, cls_detail = {}, {}, {}
for d in json.load(open(f"{B}/_p26_gate_classes.json")):
    k = (d["expr_a"], d["expr_b"])
    if k in vb:
        c = class_of(d); cls_v[c] = vb[k]; cls_k[c] = k
        rr = regate.get(k)
        cls_detail[c] = (rr or {}).get("detail", "")
pin = [c for c, k in cls_k.items() if (PIN_A in k[0] and PIN_B in k[1]) or (PIN_A in k[1] and PIN_B in k[0])]
assert len(pin) == 1, f"pin matched {len(pin)}"
cls_v[pin[0]] = "FAIL-PINNED"
print("class verdicts:", dict(collections.Counter(cls_v.values())))

W = [tuple(sorted(p)) for p in json.load(open(f"{B}/_confinement_withdrawn.json"))]
Wset = set(W)
out, det, miss = {}, {}, 0
S = json.load(open(f"{B}/_cov_FINAL_P31AB2_20260913.json"))
for a in S.get("assumptions") or []:
    if a.get("type") != "ConfinementAssumption": continue
    p = tuple(sorted((a["expr_a"], a["expr_b"])))
    if p not in Wset: continue
    c = class_of(a); v = cls_v.get(c)
    if v is None: miss += 1; continue
    out["\x00".join(p)] = v
    det["\x00".join(p)] = cls_detail.get(c, "")
print("pairs classified:", len(out), "unmapped:", miss)
print("SPLIT:", dict(collections.Counter(out.values())))
reasons = collections.Counter()
for k, v in out.items():
    if not v.startswith("FAIL"):
        d = det.get(k, "")
        if "both ways" in d: reasons[f"{v}: snapshot records a member both ways"] += 1
        elif "dead knob" in d: reasons[f"{v}: dead knob (flip did not flip)"] += 1
        elif d: reasons[f"{v}: {d[60:130]}"] += 1
        else: reasons[f"{v}: (no re-gate detail)"] += 1
print("UNEVIDENCED REASONS:", json.dumps(dict(reasons), indent=1))
json.dump(out, open(f"{B}/_p40_pair_verdicts.json", "w"), indent=0)
json.dump(dict(reasons), open(f"{B}/_p40_unevidenced_reasons.json", "w"), indent=1)
print("P40A-DONE")
