#!/usr/bin/env python3
"""report.py — aggregate the shakedown into counts that are never collapsed.

Reads `manifest.jsonl` (the resumable checkpoint) and `results/*.json` (the
per-endpoint detail) and writes `SUMMARY.json` plus the numeric body of
`REPORT.md`.

The counts are kept SEPARATE on purpose, per the shakedown spec:

    ran_clean        every stage ran and the checker returned a verdict
    no_paths         the runner produced no dump at all
    failed           a named stage failed — every one is listed individually
    harness_error    this harness, not the endpoint (also listed individually)

`complete: false` is a PASS and is counted under ran_clean.
"""
from __future__ import annotations

import collections
import glob
import json
import os
import sys

SHAKE = "/home/dev/project/reports/autolab/shakedown"
SCAFFOLD = "/home/dev/project/reports/autolab/entrypoints/scaffold"


def load():
    recs = {}
    for line in open(f"{SHAKE}/manifest.jsonl"):
        line = line.strip()
        if not line:
            continue
        r = json.loads(line)
        recs[r["endpoint"]] = r          # last wins, so a re-run supersedes
    return recs


def main():
    recs = load()
    ids = sorted(d for d in os.listdir(SCAFFOLD)
                 if os.path.isdir(os.path.join(SCAFFOLD, d)))
    detail = {}
    for f in glob.glob(f"{SHAKE}/results/*.json"):
        eid = os.path.basename(f)[:-5]
        try:
            detail[eid] = json.load(open(f))
        except Exception:
            pass

    buckets = collections.defaultdict(list)
    for eid in ids:
        r = recs.get(eid)
        if r is None:
            buckets["not_attempted"].append(eid)
            continue
        v = r.get("verdict")
        if v == "ran_clean":
            buckets["ran_clean"].append(eid)
        elif v == "no_paths":
            buckets["no_paths"].append(eid)
        elif v == "harness_error":
            buckets["harness_error"].append(eid)
        else:
            buckets["failed"].append(eid)

    failures = []
    for eid in buckets["failed"] + buckets["harness_error"]:
        d = detail.get(eid) or {}
        for f in (d.get("failures") or ()):
            failures.append({"endpoint": eid, "stage": f.get("stage"),
                             "type": f.get("type"),
                             "message": f.get("message"),
                             "file": f.get("file")})
        if not (d.get("failures") or ()):
            r = recs.get(eid, {})
            failures.append({"endpoint": eid, "stage": "harness",
                             "type": "no_result_json",
                             "message": r.get("harness_error")
                                        or f"run_rc={r.get('run_rc')} "
                                           f"pipeline_rc={r.get('pipeline_rc')} "
                                           f"run_timeout={r.get('run_timeout')} "
                                           f"pipeline_timeout={r.get('pipeline_timeout')}"})

    # ---- reach ------------------------------------------------------------
    reach = []
    for eid in ids:
        d = detail.get(eid)
        if not d or not d.get("per_dump"):
            continue
        reach.append({"endpoint": eid,
                      "declared": d.get("declared_target_functions", 0),
                      "best": d.get("reach_best", 0),
                      "worst": d.get("reach_worst", 0),
                      "dumps": d.get("dumps_on_disk", 0),
                      "chosen": d.get("chosen_dump"),
                      "reached": (d.get("per_dump") or [{}])[0].get("reached")})
    reach.sort(key=lambda r: -r["best"])

    # ---- RC-1 blast radius -------------------------------------------------
    profiles = []
    for eid in ids:
        d = detail.get(eid)
        if not d:
            continue
        if d.get("reads_profiles"):
            profiles.append({"endpoint": eid,
                             "select_star": d.get("profiles_select_star"),
                             "columns": d.get("profiles_columns")})

    # sub-counts that must not be folded into the four buckets
    zero_pc = sorted(e for e in ids
                     if detail.get(e) and (detail[e].get("path_conditions_max") or 0) == 0)
    zero_reach = sorted(r["endpoint"] for r in reach if r["best"] == 0)

    out = {
        "scaffolded": len(ids),
        "attempted": len(ids) - len(buckets["not_attempted"]),
        "counts": {k: len(v) for k, v in sorted(buckets.items())},
        "buckets": {k: sorted(v) for k, v in sorted(buckets.items())},
        "failures": failures,
        "reach": reach,
        "profiles_readers": profiles,
        "reach_stats": {
            "endpoints_measured": len(reach),
            "zero_reach": sum(1 for r in reach if r["best"] == 0),
            "max": max((r["best"] for r in reach), default=0),
            "median": (sorted(r["best"] for r in reach)[len(reach) // 2]
                       if reach else None),
            "total_distinct_reached": len(
                {t for eid in detail
                 for dd in (detail[eid].get("per_dump") or ())
                 for t in (dd.get("reached") or ())}),
        },
        "ran_clean_but_no_path_conditions": {
            "count": len(zero_pc),
            "note": "a sub-count of ran_clean, NOT a separate verdict: the run "
                    "wrote a dump and every stage passed, but the dump records "
                    "no path condition, so there is no branch to be complete "
                    "about",
            "endpoints": zero_pc,
        },
        "zero_target_function_reach": {"count": len(zero_reach),
                                       "endpoints": zero_reach},
        "completion_verdicts": collections.Counter(
            str((detail[e].get("completion") or {}).get("complete"))
            for e in detail if detail[e].get("completion")),
    }
    out["completion_verdicts"] = dict(out["completion_verdicts"])
    json.dump(out, open(f"{SHAKE}/SUMMARY.json", "w"), indent=2)

    print(json.dumps({"scaffolded": out["scaffolded"],
                      "no_path_conditions": out["ran_clean_but_no_path_conditions"]["count"],
                      "attempted": out["attempted"],
                      "counts": out["counts"],
                      "reach_stats": out["reach_stats"],
                      "completion_verdicts": out["completion_verdicts"],
                      "profiles_readers": len(profiles)}, indent=2))
    for f in failures:
        print(f"FAIL {f['endpoint']:44s} {f['stage']}:{f['type']} "
              f"{(f.get('message') or '')[:160]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
