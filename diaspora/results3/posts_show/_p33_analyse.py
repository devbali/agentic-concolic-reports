#!/usr/bin/env python3
"""P33 step 2 — price each criterion's GATE and score the reuse of the probes
the running gate has already spent. Read-only, seconds, no cage needed.

Inputs (all already on disk, none written by this script's inputs):
  _p33_criteria.json          the projections (from _p33_criteria.py)
  _p26_gate_classes.json      the DECLARED list the running gate is testing
  _p26_achk_derive.ckpt.jsonl the gate's OWN `_profile_representatives` cache,
                              i.e. the MEASURED (vi) probe count per decision
                              on the whole 232 523-dump batch dir
  _p26_gate_v2.log            what the running gate has completed, by scenario

Output: _p33_gatecost.json + a printed table.
"""
import collections
import json
import os
import re
import sys

B = os.path.dirname(os.path.abspath(__file__))

CRIT = json.load(open(os.path.join(B, "_p33_criteria.json")))
DECL = json.load(open(os.path.join(B, "_p26_gate_classes.json")))
TOTAL_WANTED = 111285          # the gate's own "[N distinct probes needed]" line
RATE = float(os.environ.get("RATE", "1.0"))     # measured probes/s

# ---- 1. the gate's measured (vi) probes per decision -----------------------
# Read at 02:20 from the LIVE _p26_achk_derive.ckpt.jsonl (109 entries, 28 with
# representatives, 109 927 in total) and matched 1-1 onto the 28 declared
# decisions with a one-sided ("taken"/"not_taken") footprint shape by a
# bipartite matching on the carried-shape sets (28/28, unique). The gate was
# stopped externally at 04:01:59 and its SIGTERM flush rewrote that checkpoint
# with 25 of the 109 entries, so the snapshot is the record:
#   _p33_derive_snapshot_20260914.json  {expr: {reps, scen: {scenario: n}}}
SNAP = json.load(open(os.path.join(B, "_p33_derive_snapshot_20260914.json")))
MEAS = {e: {"len": v["reps"], "scen": v["scen"]} for e, v in SNAP.items()}
MEAS_TOTAL = sum(x["len"] for x in MEAS.values())

# ---- 2. what the running gate has already completed ------------------------
# `ProbeCache.execute` groups the todo by SCENARIO in first-appearance order
# and runs the chunks in that order, so a finished scenario block is a PREFIX
# of that scenario's wanted order. v1 did 27 266 auth_json probes; v2's log
# says anon_json and auth_json are through and auth_html is in flight.
log = open(os.path.join(B, "_p26_gate_v2.log")).read()
done_batches = collections.Counter(re.findall(r"scenario '([a-z_]+)'", log))
V1_AUTH_JSON = 27266
completed_scen = {"auth_json": V1_AUTH_JSON}
for sc, n in done_batches.items():
    completed_scen[sc] = completed_scen.get(sc, 0) + n * 40
order, seen = [], set()
for a in DECL:
    for e in (a["expr_a"], a["expr_b"]):
        if e not in seen:
            seen.add(e)
            order.append(e)
budget = dict(completed_scen)
COMPLETED = collections.Counter()
for e in order:
    m = MEAS.get(e)
    if not m:
        continue
    for sc, n in m["scen"].items():
        take = min(n, max(0, budget.get(sc, 0)))
        if take:
            COMPLETED[e] += take
            budget[sc] -= take
COMPLETED_TOTAL = sum(COMPLETED.values())

# ---- 3. calibration snapshot -> whole batch dir ----------------------------
A = CRIT["criteria"]["A_today"]
snapA = A["snap_reps"]
k_global = MEAS_TOTAL / max(1, sum(snapA.values()))
k_dec = {e: MEAS[e]["len"] / snapA[e] for e in MEAS if snapA.get(e)}
EXTRA = TOTAL_WANTED - MEAS_TOTAL          # composition (iii)-(v),(viii) + (vii)

print(f"CALIBRATION  measured (vi) probes {MEAS_TOTAL} over {len(MEAS)} decisions; "
      f"snapshot count for the same set {sum(snapA.get(e,0) for e in MEAS)}; "
      f"global k={k_global:.4f}")
print(f"             non-(vi) probes (composition + constructed routes) = "
      f"{TOTAL_WANTED} - {MEAS_TOTAL} = {EXTRA}")
print(f"COMPLETED    by scenario {dict(completed_scen)} -> attributed "
      f"{COMPLETED_TOTAL} (vi) probes over {len(COMPLETED)} decisions")

rows = []
for tag, C in CRIT["criteria"].items():
    snap = C.get("snap_reps") or {}
    reps = C.get("rep_decisions") or []
    proj = 0.0
    for e in reps:
        n = snap.get(e, 0)
        if not n:
            continue
        proj += n * k_dec.get(e, k_global)
    extra = EXTRA * (C["classes"] / max(1, A["classes"])) if C["classes"] else 0
    probes = proj + extra
    reuse = sum(COMPLETED[e] for e in reps if e in COMPLETED)
    cen = C.get("census") or {}
    rem_prod = (cen.get("prod") or {}).get("remaining")
    rem_16f = (cen.get("16f") or {}).get("remaining") if cen.get("16f") else None
    rows.append({
        "criterion": tag, "pairs": C["pairs"], "or_pairs": C.get("or_pairs", 0),
        "classes": C["classes"], "rep_decisions": len(reps),
        "probes_vi": round(proj), "probes_extra": round(extra),
        "probes": round(probes), "hours": round(probes / RATE / 3600, 1),
        "reuse": reuse, "reuse_pct": round(100.0 * reuse / max(1, probes), 1),
        "new_probes": round(max(0.0, probes - reuse)),
        "new_hours": round(max(0.0, probes - reuse) / RATE / 3600, 1),
        "demand_sets": C["demand_sets"],
        "remaining_prod": rem_prod, "remaining_16f": rem_16f,
        "decided": C.get("decided"), "coevaluated": C.get("coevaluated"),
        "disqualified": C.get("disqualified"),
    })

hdr = ("criterion   pairs  OR-lic classes repdec   probes   hours   reuse  reuse%"
       "  new_h  sets  REMAIN(16f)   REMAIN(prod)")
print("\n" + hdr)
print("-" * len(hdr))
for r in rows:
    print(f"{r['criterion']:<11}{r['pairs']:>6}{r['or_pairs']:>8}{r['classes']:>8}"
          f"{r['rep_decisions']:>7}{r['probes']:>9}{r['hours']:>8}{r['reuse']:>8}"
          f"{r['reuse_pct']:>7}{r['new_hours']:>7}{r['demand_sets']:>6}"
          f"  {str(r['remaining_16f']):>11}  {str(r['remaining_prod']):>13}")

json.dump({"rows": rows, "measured_vi": {e: MEAS[e]["len"] for e in MEAS},
           "completed_by_decision": dict(COMPLETED),
           "completed_by_scenario": completed_scen,
           "k_global": k_global, "extra": EXTRA,
           "total_wanted_control": TOTAL_WANTED, "rate": RATE},
          open(os.path.join(B, "_p33_gatecost.json"), "w"), indent=1)
print("\nwrote _p33_gatecost.json")
