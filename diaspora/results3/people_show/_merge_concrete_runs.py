#!/usr/bin/env python3
"""Merge the per-scenario concrete runs into the single concrete_run.json the
completion config points at (2026-09-19).

Each `concrete_run_<scenario>.json` is a LIST of scenario records (the probe's
own output shape). `mock_note_check` takes the concatenation, so merging is a
concatenation in a stable order, with a report of any scenario that recorded
an `error` — an errored scenario is kept (its calls up to the failure are real
evidence) but named, so a partial ground truth is never silently narrower.
"""
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ORDER = ["anon_handle", "anon_json", "auth_self_html", "auth_json"]


def main() -> int:
    merged, errs, missing = [], [], []
    for s in ORDER:
        p = os.path.join(HERE, f"concrete_run_{s}.json")
        if not os.path.exists(p):
            missing.append(s)
            continue
        with open(p) as fh:
            part = json.load(fh)
        for rec in part:
            if rec.get("error"):
                errs.append((rec.get("name"), str(rec["error"])[:160]))
            merged.append(rec)
    out = os.path.join(HERE, "concrete_run.json")
    with open(out, "w") as fh:
        json.dump(merged, fh, indent=1)
    ncalls = sum(len(r.get("target_calls") or ()) for r in merged)
    print(f"merged {len(merged)} scenario records ({ncalls} target calls) -> {out}")
    for n, e in errs:
        print(f"  ERRORED scenario {n}: {e}")
    if missing:
        print(f"  MISSING scenarios: {missing}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
