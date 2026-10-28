#!/usr/bin/env python3
"""Merge the per-scenario exploration summaries a parallel drive writes
(`exploration_summary_<scenario>.json`) into the canonical
`exploration_summary.json`, in the SAME schema a sequential run produces.

A sequential `run_dse.rb` writes one file whose `scenarios` list is every
scenario in SCENARIOS order; a parallel drive writes one file per scenario,
each with a single-element list. Everything else in the file is identical, so
merging is: take the shared keys from any part, concatenate the `scenarios`
lists in the canonical order, and recompute the wall clock as the MAX of the
parts (they ran concurrently, so summing would overstate it).
"""
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# The canonical order, as SCENARIOS is declared in run_dse.rb.
ORDER = ["anon_handle", "anon_json", "anon_mobile", "anon_mobile_presenter",
         "auth_self_html", "auth_other_html", "auth_json", "auth_mobile",
         "anon_remote_401"]


def main() -> int:
    parts = sorted(glob.glob(os.path.join(HERE, "exploration_summary_*.json")))
    if not parts:
        print("no per-scenario summaries found; nothing to merge")
        return 1

    merged = None
    by_name = {}
    elapsed = 0.0
    for p in parts:
        with open(p) as fh:
            d = json.load(fh)
        if merged is None:
            merged = {k: v for k, v in d.items() if k != "scenarios"}
        elapsed = max(elapsed, float(d.get("total_elapsed_seconds") or 0))
        for s in d.get("scenarios") or ():
            by_name[s["scenario"]] = s

    missing = [s for s in ORDER if s not in by_name]
    extra = [s for s in by_name if s not in ORDER]
    merged["scenarios"] = [by_name[s] for s in ORDER if s in by_name] + \
                          [by_name[s] for s in extra]
    # concurrent, so the campaign's wall clock is the longest scenario
    merged["total_elapsed_seconds"] = round(elapsed, 1)
    merged["drive_mode"] = "parallel (one JRuby per scenario, 2026-09-19)"
    if missing:
        merged["scenarios_missing"] = missing

    out = os.path.join(HERE, "exploration_summary.json")
    with open(out, "w") as fh:
        json.dump(merged, fh, indent=2)

    tot_runs = sum(s.get("runs_executed", 0) for s in merged["scenarios"])
    tot_paths = sum(s.get("distinct_paths", 0) for s in merged["scenarios"])
    drained = sum(1 for s in merged["scenarios"] if s.get("worklist_exhausted"))
    print(f"merged {len(parts)} parts -> {out}")
    print(f"  scenarios={len(merged['scenarios'])} drained={drained} "
          f"runs={tot_runs} paths={tot_paths} wall={merged['total_elapsed_seconds']}s")
    if missing:
        print(f"  MISSING scenarios: {missing}")
    for s in merged["scenarios"]:
        print(f"  {s['scenario']:24s} runs={s.get('runs_executed'):>7} "
              f"paths={s.get('distinct_paths'):>6} "
              f"drained={str(s.get('worklist_exhausted')):>5} "
              f"capped_by={s.get('capped_by')!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
