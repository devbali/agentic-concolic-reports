#!/usr/bin/env python3
"""P34 — RE-WITHDRAWAL after the multi-base re-gate (§102).

Same CLASS-WHOLE policy as `_p32_withdraw.py` (unchanged, and not invented
here: `coverage_report.py` states it above `withdrawn_pairs=`). The ONE change
is the verdict map it withdraws against:

    base map      `_p26_gate_results.json`        (the 1-base gate, 1363 classes)
    overridden by `_p32_regate_results.json`      (243 N-T classes at ACHK_BASES=8)
    overridden by `_p32_regate_NC_results.json`   (61 N-C classes at ACHK_BASES=8)
                                                   -- when either file exists

RESTORE BY EXPLICIT VERDICT, NEVER BY NEGATION (coordinator, 2026-09-14):
a class is restored ONLY when its re-gate row says `verdict == "PASS"` AND
`bases_realising >= 1`.  A row that is missing, ERROR, NOT-TESTABLE,
NOT-COMPARABLE or FAIL keeps the class withdrawn.  "not FAIL" is not a
restoration.

PINNED REFUTATION, NEVER AUTO-RESTORED (§96.4): the class containing
`findpublic_like_1_not_found x as_api_response_1_row_text_empty` is genuinely
refuted (FAIL on 6 of 8 bases, "(i) flip-A changed 1 shape OUTSIDE
footprint(A): Photo.url") and reads NOT-TESTABLE in the 1-base results, i.e. it
is INSIDE the re-gate bucket.  It is forced to stay withdrawn whatever the
re-gate says, and the run ABORTS if the pin does not match exactly one class.

Also writes `_p34_restore_grades.json`: per restored class, the evidence grade
(`bases_probed` / `bases_realising` / `bases_passing` / `bases_failing`), which
POLICY_HEADER needs at closure -- a licence resting on 1 realising base is not
the same as one resting on 8.
"""
import json, os, re, sys
from collections import Counter, defaultdict

B = os.path.dirname(os.path.abspath(__file__))
SUMMARY = os.environ.get("SUMMARY", os.path.join(B, "_cov_FINAL_P31AB2_20260913.json"))
OUT     = os.environ.get("OUT",     os.path.join(B, "_confinement_withdrawn.json"))
REPORT  = os.environ.get("REPORT",  os.path.join(B, "_p34_withdraw_report.json"))
GRADES  = os.environ.get("GRADES",  os.path.join(B, "_p34_restore_grades.json"))

PIN_A = "findpublic_like_1_not_found"
PIN_B = "as_api_response_1_row_text_empty"

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

def rows(path):
    if not os.path.exists(path):
        print(f"  (absent, skipped) {os.path.basename(path)}")
        return []
    r = json.load(open(path))
    print(f"  {os.path.basename(path)}: {len(r)} rows  "
          + json.dumps(dict(Counter(x['verdict'] for x in r))))
    return r

print("verdict sources, in override order:")
base_rows   = rows(os.path.join(B, "_p26_gate_results.json"))
regate_rows = rows(os.path.join(B, "_p32_regate_results.json"))
nc_rows     = rows(os.path.join(B, "_p32_regate_NC_results.json"))

verdict_by_key, grade_by_key = {}, {}
for r in base_rows:
    verdict_by_key[(r["expr"], r["expr_b"])] = r["verdict"]
restored_keys = set()
for src, rs in (("NT", regate_rows), ("NC", nc_rows)):
    for r in rs:
        k = (r["expr"], r["expr_b"])
        g = {f: r.get(f) for f in ("bases_probed", "bases_realising",
                                   "bases_passing", "bases_failing")}
        # EXPLICIT verdict only. A PASS with no realising base is NOT evidence:
        # criterion (vi) never ran on a base that realised the premise.
        if r["verdict"] == "PASS" and (r.get("bases_realising") or 0) >= 1:
            old = verdict_by_key.get(k)
            verdict_by_key[k] = "PASS"
            grade_by_key[k] = dict(g, source=src, was=old, base_verdicts=r.get("base_verdicts"))
            restored_keys.add(k)
        else:
            # keep whatever the 1-base gate said; record the re-gate's own word
            grade_by_key.setdefault(k, dict(g, source=src, was=verdict_by_key.get(k),
                                            regate_verdict=r["verdict"]))
print(f"classes restored to PASS by the re-gate(s): {len(restored_keys)}")

dec = json.load(open(os.path.join(B, "_p26_gate_classes.json")))
cls_verdict, cls_detail, cls_key = {}, {}, {}
for d in dec:
    k = (d["expr_a"], d["expr_b"])
    v = verdict_by_key.get(k)
    if v is None:
        continue
    c = class_of(d)
    cls_verdict[c] = v
    cls_key[c] = k
    cls_detail[c] = ""

# --- the pinned refutation -------------------------------------------------
pinned = [c for c, k in cls_key.items()
          if (PIN_A in k[0] and PIN_B in k[1]) or (PIN_A in k[1] and PIN_B in k[0])]
if len(pinned) != 1:
    sys.exit(f"ABORT: the pinned refutation matched {len(pinned)} classes, expected 1. "
             "Do not proceed -- a blanket restore would wrongly restore it.")
pin_cls = pinned[0]
print(f"pinned refutation class: verdict was {cls_verdict[pin_cls]!r} -> forced FAIL-PINNED")
cls_verdict[pin_cls] = "FAIL-PINNED"
restored_keys.discard(cls_key[pin_cls])

print("class verdicts after merge:", dict(Counter(cls_verdict.values())), flush=True)
print(f"reading {SUMMARY} ({os.path.getsize(SUMMARY)/1e6:.0f} MB)", flush=True)
S = json.load(open(SUMMARY))
A = S.get("assumptions") or []

withdrawn, kept, untested = [], 0, 0
by_verdict = Counter(); restored_pairs = 0
grades_out = defaultdict(lambda: {"pairs": 0})
for a in A:
    if a.get("type") != "ConfinementAssumption":
        continue
    c = class_of(a)
    v = cls_verdict.get(c)
    if v is None:
        untested += 1; continue
    if v == "PASS":
        kept += 1
        k = cls_key.get(c)
        if k in restored_keys:
            restored_pairs += 1
            g = grade_by_key.get(k) or {}
            key = f"{g.get('bases_realising')}/{g.get('bases_probed')} realising, " \
                  f"{g.get('bases_passing')} passing, {g.get('bases_failing')} failing"
            grades_out[key]["pairs"] += 1
        continue
    withdrawn.append([a["expr_a"], a["expr_b"]])
    by_verdict[v] += 1

seen, uniq = set(), []
for p in withdrawn:
    t = tuple(sorted(p))
    if t not in seen:
        seen.add(t); uniq.append(list(p))
json.dump(uniq, open(OUT, "w"), indent=0)
rep = {"pairs_withdrawn": len(uniq), "pairs_kept_PASS": kept,
       "pairs_RESTORED_by_regate": restored_pairs,
       "pairs_in_untested_class": untested,
       "withdrawn_by_verdict": dict(by_verdict),
       "classes_restored": len(restored_keys),
       "evidence_grades_of_restored_pairs": {k: v["pairs"] for k, v in grades_out.items()}}
json.dump(rep, open(REPORT, "w"), indent=1)
json.dump({json.dumps(list(k)): v for k, v in grade_by_key.items()},
          open(GRADES, "w"), indent=1)
print(json.dumps(rep, indent=1))
print(f"wrote {OUT} ({len(uniq)} pairs)")
print("P34-WITHDRAW-V2-DONE")
